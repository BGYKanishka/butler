#import <AppKit/AppKit.h>
#import "LlamaWrapper.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"
#import "llama.h"
#include "mtmd.h"
#include "mtmd-helper.h"
#pragma clang diagnostic pop
#include <string>
#include <vector>

@implementation LlamaWrapper {
    struct llama_model *_model;
    struct llama_context *_ctx;
    const struct llama_vocab *_vocab;
    BOOL _isCancelled;
    
    struct mtmd_context *_mtmd_ctx;
    
    std::vector<llama_token> _last_tokens;
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
    
    // Find common prefix with previous generation to reuse KV cache
    int n_past = 0;
    while (n_past < _last_tokens.size() && n_past < tokens_list.size() && _last_tokens[n_past] == tokens_list[n_past]) {
        n_past++;
    }
    
    // Clear the divergent part of the memory
    llama_memory_t mem = llama_get_memory(_ctx);
    if (mem && n_past < _last_tokens.size()) {
        llama_memory_seq_rm(mem, -1, n_past, -1);
    }
    
    // Sampler setup
    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    struct llama_sampler * smpl = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(smpl, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(smpl, llama_sampler_init_greedy());
    
    // Evaluate only the NEW tokens
    int n_eval = n_tokens - n_past;
    if (n_eval > 0) {
        llama_batch batch = llama_batch_init(n_eval, 0, 1);
        batch.n_tokens = n_eval;
        for (int i = 0; i < n_eval; i++) {
            batch.token[i] = tokens_list[n_past + i];
            batch.pos[i] = n_past + i;
            batch.seq_id[i][0] = 0;
            batch.n_seq_id[i] = 1;
            batch.logits[i] = false;
        }
        batch.logits[n_eval - 1] = true;
        
        if (llama_decode(_ctx, batch)) {
            llama_sampler_free(smpl);
            return; // Error decoding
        }
        llama_batch_free(batch);
    }
    
    int n_cur = n_tokens;
    int n_generated = 0;
    
    // Save prompt tokens to last tokens
    _last_tokens = tokens_list;
    
    while (n_generated < maxTokens) {
        if (_isCancelled) break;
        
        llama_token new_token_id = llama_sampler_sample(smpl, _ctx, -1);
        llama_sampler_accept(smpl, new_token_id);
        
        if (llama_vocab_is_eog(_vocab, new_token_id)) {
            break;
        }
        
        _last_tokens.push_back(new_token_id);
        
        char buf[128];
        int n_chars = llama_token_to_piece(_vocab, new_token_id, buf, sizeof(buf), 0, true);
        if (n_chars > 0 && n_chars < sizeof(buf)) {
            buf[n_chars] = '\0';
            NSString *tokenStr = [NSString stringWithUTF8String:buf];
            if (tokenStr && onToken) {
                onToken(tokenStr);
            }
        }
        
        llama_batch batch = llama_batch_init(1, 0, 1);
        batch.n_tokens = 1;
        batch.token[0] = new_token_id;
        batch.pos[0] = n_cur;
        batch.seq_id[0][0] = 0;
        batch.n_seq_id[0] = 1;
        batch.logits[0] = true;
        
        if (llama_decode(_ctx, batch)) {
            llama_batch_free(batch);
            break;
        }
        llama_batch_free(batch);
        
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
    
    llama_pos new_n_past = 0;
    int32_t n_batch = 2048; // A reasonable batch size
    
    int eval_res = mtmd_helper_eval_chunks(_mtmd_ctx, _ctx, chunks, 0, 0, n_batch, true, &new_n_past);
    if (eval_res != 0) {
        mtmd_input_chunks_free(chunks);
        [self generateStreaming:prompt temperature:temperature maxTokens:maxTokens onToken:onToken];
        return;
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
        
        llama_batch batch = llama_batch_init(1, 0, 1);
        batch.n_tokens = 1;
        batch.token[0] = new_token_id;
        batch.pos[0] = new_n_past;
        batch.seq_id[0][0] = 0;
        batch.n_seq_id[0] = 1;
        batch.logits[0] = true;
        
        if (llama_decode(_ctx, batch)) {
            llama_batch_free(batch);
            break;
        }
        llama_batch_free(batch);
        
        new_n_past += 1;
        
        n_generated += 1;
    }
    
    llama_sampler_free(smpl);
}

- (void)cancel {
    _isCancelled = YES;
}

- (BOOL)saveStateToPath:(NSString *)path prompt:(NSString *)prompt error:(NSError **)error {
    if (!_model || !_ctx || !_vocab) return NO;
    _isCancelled = NO;
    
    // Tokenize the prompt
    const char *c_prompt = [prompt UTF8String];
    if (!c_prompt) return NO;
    std::string prompt_str = c_prompt;
    std::vector<llama_token> tokens_list(prompt_str.length() + 2);
    
    int n_tokens = llama_tokenize(_vocab, prompt_str.c_str(), (int32_t)prompt_str.length(), tokens_list.data(), (int32_t)tokens_list.size(), true, true);
    if (n_tokens < 0) {
        tokens_list.resize(-n_tokens);
        n_tokens = llama_tokenize(_vocab, prompt_str.c_str(), (int32_t)prompt_str.length(), tokens_list.data(), (int32_t)tokens_list.size(), true, true);
    }
    tokens_list.resize(n_tokens);
    
    int max_context = llama_n_ctx(_ctx);
    int safe_limit = max_context - 512;
    if (safe_limit < 512) safe_limit = 512;
    
    if (n_tokens > safe_limit) {
        tokens_list.resize(safe_limit);
        n_tokens = safe_limit;
    }
    
    // Find common prefix with previous generation
    int n_past = 0;
    while (n_past < _last_tokens.size() && n_past < tokens_list.size() && _last_tokens[n_past] == tokens_list[n_past]) {
        n_past++;
    }
    
    // Clear divergent memory
    llama_memory_t mem = llama_get_memory(_ctx);
    if (mem && n_past < _last_tokens.size()) {
        llama_memory_seq_rm(mem, -1, n_past, -1);
    }
    
    // Decode new tokens
    int n_eval = n_tokens - n_past;
    if (n_eval > 0) {
        // Evaluate in chunks to avoid blowing up memory if prompt is huge
        int batch_size = 512;
        for (int i = 0; i < n_eval; i += batch_size) {
            if (_isCancelled) return NO;
            int chunk_size = std::min(batch_size, n_eval - i);
            llama_batch batch = llama_batch_init(chunk_size, 0, 1);
            batch.n_tokens = chunk_size;
            for (int j = 0; j < chunk_size; j++) {
                batch.token[j] = tokens_list[n_past + i + j];
                batch.pos[j] = n_past + i + j;
                batch.seq_id[j][0] = 0;
                batch.n_seq_id[j] = 1;
                batch.logits[j] = false; // We don't need logits just for saving context
            }
            if (llama_decode(_ctx, batch)) {
                llama_batch_free(batch);
                if (error) *error = [NSError errorWithDomain:@"Llama" code:4 userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode context batch"}];
                return NO;
            }
            llama_batch_free(batch);
        }
    }
    
    _last_tokens = tokens_list;
    
    // Save to binary file
    bool success = llama_state_save_file(_ctx, [path UTF8String], _last_tokens.data(), _last_tokens.size());
    if (!success) {
        if (error) *error = [NSError errorWithDomain:@"Llama" code:5 userInfo:@{NSLocalizedDescriptionKey: @"Failed to save binary state"}];
    }
    return success;
}

- (BOOL)loadStateFromPath:(NSString *)path error:(NSError **)error {
    if (!_ctx) return NO;
    
    uint32_t n_ctx = llama_n_ctx(_ctx);
    std::vector<llama_token> tokens_out(n_ctx);
    size_t count = 0;
    
    bool success = llama_state_load_file(_ctx, [path UTF8String], tokens_out.data(), tokens_out.size(), &count);
    if (success) {
        tokens_out.resize(count);
        _last_tokens = tokens_out;
        return YES;
    }
    
    if (error) *error = [NSError errorWithDomain:@"Llama" code:6 userInfo:@{NSLocalizedDescriptionKey: @"Failed to load binary state"}];
    return NO;
}

@end
