#import <AppKit/AppKit.h>
#import "LlamaWrapper.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"
#import "llama.h"
#include "mtmd.h"
#pragma clang diagnostic pop
#include <string>
#include <vector>

@implementation LlamaWrapper {
    struct llama_model *_model;
    struct llama_context *_ctx;
    const struct llama_vocab *_vocab;
    BOOL _isCancelled;
    
    struct mtmd_context *_mtmd_ctx;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        llama_backend_init();
    }
    return self;
}

- (void)dealloc {
    [self unload];
    llama_backend_free();
}

- (BOOL)loadModel:(NSString *)modelPath contextSize:(int)contextSize error:(NSError **)error {
    [self unload];
    
    llama_model_params model_params = llama_model_default_params();
    _model = llama_model_load_from_file([modelPath UTF8String], model_params);
    if (!_model) {
        if (error) *error = [NSError errorWithDomain:@"Llama" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to load model"}];
        return NO;
    }
    
    _vocab = llama_model_get_vocab(_model);
    
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = contextSize;
    _ctx = llama_init_from_model(_model, ctx_params);
    if (!_ctx) {
        llama_model_free(_model);
        _model = NULL;
        _vocab = NULL;
        if (error) *error = [NSError errorWithDomain:@"Llama" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create context"}];
        return NO;
    }
    
    return YES;
}

- (BOOL)loadVisionModel:(NSString *)modelPath mmprojPath:(NSString *)mmprojPath contextSize:(int)contextSize error:(NSError **)error {
    if (![self loadModel:modelPath contextSize:contextSize error:error]) {
        return NO;
    }
    
    struct mtmd_context_params mparams = mtmd_context_params_default();
    _mtmd_ctx = mtmd_init_from_file([mmprojPath UTF8String], _model, mparams);
    if (!_mtmd_ctx) {
        if (error) *error = [NSError errorWithDomain:@"Llama" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Failed to load mtmd projector"}];
        return NO;
    }
    
    return YES;
}

- (void)unload {
    if (_ctx) {
        llama_free(_ctx);
        _ctx = NULL;
    }
    if (_model) {
        llama_model_free(_model);
        _model = NULL;
        _vocab = NULL;
    }
    
    if (_mtmd_ctx) {
        mtmd_free(_mtmd_ctx);
        _mtmd_ctx = NULL;
    }
}

- (void)generateStreaming:(NSString *)prompt temperature:(float)temperature maxTokens:(int)maxTokens onToken:(void (^)(NSString *token))onToken {
    if (!_model || !_ctx || !_vocab) return;
    _isCancelled = NO;
    llama_memory_t mem = llama_get_memory(_ctx);
    if (mem) {
        llama_memory_clear(mem, true);
    }
    
    // Tokenize
    const char *c_prompt = [prompt UTF8String];
    if (!c_prompt) return;
    std::string prompt_str = c_prompt;
    std::vector<llama_token> tokens_list(prompt_str.length() + 2); // rough estimate
    
    int n_tokens = llama_tokenize(_vocab, prompt_str.c_str(), (int32_t)prompt_str.length(), tokens_list.data(), (int32_t)tokens_list.size(), true, true);
    if (n_tokens < 0) {
        tokens_list.resize(-n_tokens);
        n_tokens = llama_tokenize(_vocab, prompt_str.c_str(), (int32_t)prompt_str.length(), tokens_list.data(), (int32_t)tokens_list.size(), true, true);
    }
    tokens_list.resize(n_tokens);
    
    // Sampler setup
    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    struct llama_sampler * smpl = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(smpl, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(smpl, llama_sampler_init_greedy());
    
    // Evaluate prompt
    llama_batch batch = llama_batch_get_one(tokens_list.data(), n_tokens);
    
    if (llama_decode(_ctx, batch)) {
        llama_sampler_free(smpl);
        return; // Error decoding
    }
    
    int n_cur = n_tokens;
    int n_generated = 0;
    
    while (n_generated < maxTokens) {
        if (_isCancelled) break;
        
        llama_token new_token_id = llama_sampler_sample(smpl, _ctx, -1);
        llama_sampler_accept(smpl, new_token_id);
        
        if (llama_vocab_is_eog(_vocab, new_token_id)) {
            break;
        }
        
        char buf[128];
        int n_chars = llama_token_to_piece(_vocab, new_token_id, buf, sizeof(buf), 0, true);
        if (n_chars > 0 && n_chars < sizeof(buf)) {
            buf[n_chars] = '\0';
            NSString *tokenStr = [NSString stringWithUTF8String:buf];
            if (tokenStr && onToken) {
                onToken(tokenStr);
            }
        }
        
        // Prepare next batch with the single generated token
        batch = llama_batch_get_one(&new_token_id, 1);
        if (llama_decode(_ctx, batch)) {
            break;
        }
        
        n_cur += 1;
        n_generated += 1;
    }
    
    llama_sampler_free(smpl);
}

- (void)generateVisionStreaming:(NSString *)prompt imagePath:(NSString *)imagePath temperature:(float)temperature maxTokens:(int)maxTokens onToken:(void (^)(NSString *))onToken {
    if (!_mtmd_ctx) {
        [self generateStreaming:prompt temperature:temperature maxTokens:maxTokens onToken:onToken];
        return;
    }
    
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:imagePath];
    if (!image) {
        [self generateStreaming:prompt temperature:temperature maxTokens:maxTokens onToken:onToken];
        return;
    }
    
    CGImageRef cgImage = [image CGImageForProposedRect:nil context:nil hints:nil];
    if (!cgImage) {
        [self generateStreaming:prompt temperature:temperature maxTokens:maxTokens onToken:onToken];
        return;
    }
    
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    unsigned char *rawData = (unsigned char*) calloc(height * width * 4, sizeof(unsigned char));
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(rawData, width, height, 8, width * 4, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    // Extract RGB from RGBA
    unsigned char *rgbData = (unsigned char *)malloc(width * height * 3);
    for (int i = 0; i < width * height; i++) {
        rgbData[i*3] = rawData[i*4];
        rgbData[i*3+1] = rawData[i*4+1];
        rgbData[i*3+2] = rawData[i*4+2];
    }
    free(rawData);
    
    mtmd_bitmap * bmp = mtmd_bitmap_init((uint32_t)width, (uint32_t)height, rgbData);
    
    NSString *finalPrompt = prompt;
    if (![finalPrompt containsString:@"<__media__>"]) {
        finalPrompt = [NSString stringWithFormat:@"<__media__>\n%@", prompt];
    }
    
    mtmd_input_text txt = { [finalPrompt UTF8String], finalPrompt.length, true, true };
    mtmd_input_chunks * chunks = mtmd_input_chunks_init();
    
    const mtmd_bitmap * bmps[] = { bmp };
    int tokenize_res = mtmd_tokenize(_mtmd_ctx, chunks, &txt, bmps, 1);
    
    free(rgbData);
    mtmd_bitmap_free(bmp);
    
    if (tokenize_res != 0) {
        mtmd_input_chunks_free(chunks);
        [self generateStreaming:prompt temperature:temperature maxTokens:maxTokens onToken:onToken];
        return;
    }
    
    llama_memory_t mem = llama_get_memory(_ctx);
    if (mem) llama_memory_clear(mem, true);
    _isCancelled = NO;
    
    size_t num_chunks = mtmd_input_chunks_size(chunks);
    for (size_t i = 0; i < num_chunks; i++) {
        const mtmd_input_chunk * chunk = mtmd_input_chunks_get(chunks, i);
        if (mtmd_input_chunk_get_type(chunk) == MTMD_INPUT_CHUNK_TYPE_TEXT) {
            size_t n_tokens_output = 0;
            const llama_token * tokens = mtmd_input_chunk_get_tokens_text(chunk, &n_tokens_output);
            if (n_tokens_output > 0) {
                llama_batch batch = llama_batch_get_one((llama_token*)tokens, (int32_t)n_tokens_output);
                if (llama_decode(_ctx, batch)) break;
            }
        } else if (mtmd_input_chunk_get_type(chunk) == MTMD_INPUT_CHUNK_TYPE_IMAGE) {
            mtmd_batch * mbatch = mtmd_batch_init(_mtmd_ctx);
            if (mtmd_batch_add_chunk(mbatch, chunk) == 0) {
                if (mtmd_batch_encode(mbatch) == 0) {
                    float * embd = mtmd_batch_get_output_embd(mbatch, chunk);
                    size_t n_img_tokens = mtmd_input_chunk_get_n_tokens(chunk);
                    
                    llama_batch batch = llama_batch_init((int32_t)n_img_tokens, 1, 1);
                    batch.embd = embd;
                    for (size_t j = 0; j < n_img_tokens; j++) {
                        batch.token[j]    = 0;
                        batch.pos[j]      = (llama_pos)j;
                        batch.n_seq_id[j] = 1;
                        batch.seq_id[j][0] = 0;
                        batch.logits[j]   = false;
                    }
                    if (llama_decode(_ctx, batch)) {}
                    llama_batch_free(batch);
                }
            }
            mtmd_batch_free(mbatch);
        }
    }
    
    mtmd_input_chunks_free(chunks);
    
    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    struct llama_sampler * smpl = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(smpl, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(smpl, llama_sampler_init_greedy());
    
    int n_generated = 0;
    while (n_generated < maxTokens) {
        if (_isCancelled) break;
        
        llama_token new_token_id = llama_sampler_sample(smpl, _ctx, -1);
        llama_sampler_accept(smpl, new_token_id);
        if (llama_vocab_is_eog(_vocab, new_token_id)) break;
        
        char buf[128];
        int n_chars = llama_token_to_piece(_vocab, new_token_id, buf, sizeof(buf), 0, true);
        if (n_chars > 0 && n_chars < sizeof(buf)) {
            buf[n_chars] = '\0';
            NSString *tokenStr = [NSString stringWithUTF8String:buf];
            if (tokenStr && onToken) onToken(tokenStr);
        }
        
        llama_batch batch = llama_batch_get_one(&new_token_id, 1);
        if (llama_decode(_ctx, batch)) break;
        
        n_generated += 1;
    }
    
    llama_sampler_free(smpl);
}

- (void)cancel {
    _isCancelled = YES;
}

@end
