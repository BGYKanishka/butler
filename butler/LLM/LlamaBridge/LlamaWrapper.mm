#import <AppKit/AppKit.h>
#import "LlamaWrapper.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"
#import "llama.h"
#include "mtmd.h"
#include "mtmd-helper.h"
#pragma clang diagnostic pop
#include <algorithm>
#include <string>
#include <vector>


static struct llama_sampler * ButlerMakeSampler(float temperature, int32_t n_vocab) {
    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    struct llama_sampler * smpl = llama_sampler_chain_init(sparams);
    // Penalise tokens already produced in this answer (last 256), not the prompt.
    llama_sampler_chain_add(smpl, llama_sampler_init_penalties(n_vocab, 256, 1.15f, 0.05f, 0.05f));
    if (temperature <= 0.01f) {
        llama_sampler_chain_add(smpl, llama_sampler_init_greedy());
    } else {
        llama_sampler_chain_add(smpl, llama_sampler_init_top_k(40));
        llama_sampler_chain_add(smpl, llama_sampler_init_top_p(0.90f, 1));
        llama_sampler_chain_add(smpl, llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(smpl, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    }
    return smpl;
}

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
    // The KV cache dies with the context, so the token mirror MUST die with it. Leaving stale
    // tokens here made the next prompt "reuse" a prefix (the system prompt + project context)
    // that no longer existed in the fresh context, so the model never saw the project.
    _last_tokens.clear();
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
    if (n_tokens <= 0) return;
    tokens_list.resize(n_tokens);
    
    // Safety net: a prompt that does not fit the context window used to make llama_decode fail
    // silently (no answer at all). PromptBuilder budgets the prompt, but if it is still too long,
    // keep the head (system prompt + project context) and the tail (latest turns).
    const int n_ctx = (int)llama_n_ctx(_ctx);
    const int max_prompt = n_ctx - maxTokens - 16;
    if (max_prompt < 256) return;
    if (n_tokens > max_prompt) {
        NSLog(@"[LlamaWrapper] Prompt is %d tokens but only %d fit — trimming the middle", n_tokens, max_prompt);
        const int head = (max_prompt * 3) / 5;
        const int tail = max_prompt - head;
        std::vector<llama_token> trimmed;
        trimmed.reserve(max_prompt);
        trimmed.insert(trimmed.end(), tokens_list.begin(), tokens_list.begin() + head);
        trimmed.insert(trimmed.end(), tokens_list.end() - tail, tokens_list.end());
        tokens_list.swap(trimmed);
        n_tokens = (int)tokens_list.size();
    }
    
    // Find common prefix with the tokens that are actually in the KV cache.
    int n_past = 0;
    while (n_past < (int)_last_tokens.size() && n_past < n_tokens && _last_tokens[n_past] == tokens_list[n_past]) {
        n_past++;
    }
    // Always re-decode at least the final prompt token so fresh logits exist for sampling
    // (an identical repeat prompt previously left nothing to decode).
    if (n_past >= n_tokens) n_past = n_tokens - 1;
    
    // Drop everything at/after n_past (divergent prompt tail and last turn's generated tokens).
    llama_memory_t mem = llama_get_memory(_ctx);
    if (mem && !llama_memory_seq_rm(mem, -1, n_past, -1)) {
        llama_memory_clear(mem, true);
        n_past = 0;
    }
    _last_tokens.resize(n_past);
    
    // Sampler setup
    struct llama_sampler * smpl = ButlerMakeSampler(temperature, llama_vocab_n_tokens(_vocab));
    for (int i = std::max(0, n_tokens - 256); i < n_tokens; i++) {
        llama_sampler_accept(smpl, tokens_list[i]);
    }
    
    // Evaluate only the NEW tokens, in chunks (a single huge batch exceeds n_batch and fails).
    const int chunk_max = 512;
    for (int i = n_past; i < n_tokens; i += chunk_max) {
        if (_isCancelled) { llama_sampler_free(smpl); return; }
        const int n = std::min(chunk_max, n_tokens - i);
        llama_batch batch = llama_batch_init(n, 0, 1);
        batch.n_tokens = n;
        for (int j = 0; j < n; j++) {
            batch.token[j] = tokens_list[i + j];
            batch.pos[j] = i + j;
            batch.seq_id[j][0] = 0;
            batch.n_seq_id[j] = 1;
            batch.logits[j] = (i + j == n_tokens - 1);
        }
        const int rc = llama_decode(_ctx, batch);
        llama_batch_free(batch);
        if (rc != 0) {
            NSLog(@"[LlamaWrapper] llama_decode failed during prompt evaluation (rc=%d)", rc);
            llama_sampler_free(smpl);
            if (mem) llama_memory_clear(mem, true);
            _last_tokens.clear();
            return;
        }
        // Keep the mirror equal to what is really in the KV cache.
        _last_tokens.insert(_last_tokens.end(), tokens_list.begin() + i, tokens_list.begin() + i + n);
    }
    
    int n_cur = n_tokens;
    int n_generated = 0;
    const char *stop_reason = "max_tokens";
    
    while (n_generated < maxTokens) {
        if (_isCancelled) { stop_reason = "cancelled"; break; }
        
        llama_token new_token_id = llama_sampler_sample(smpl, _ctx, -1);
        llama_sampler_accept(smpl, new_token_id);
        
        if (llama_vocab_is_eog(_vocab, new_token_id)) {
            stop_reason = "end_of_turn";
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
            _last_tokens.pop_back(); // this token never made it into the KV cache
            stop_reason = "decode_failed";
            break;
        }
        llama_batch_free(batch);
        
        n_cur += 1;
        n_generated += 1;
    }
    
    // Diagnostic: answers that stop at a suspiciously fixed length (e.g. always 230 tokens) are
    // explained by this line — max_tokens means a cap, decode_failed means the KV cache filled up.
    NSLog(@"[LlamaWrapper] generation stopped: reason=%s generated=%d maxTokens=%d prompt=%d n_ctx=%d temp=%.2f",
          stop_reason, n_generated, maxTokens, n_tokens, n_ctx, temperature);
    
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
    // The vision prompt replaces the whole KV cache. Forget the text prompt we thought was cached,
    // otherwise the next text question skips re-evaluating the system prompt + project context.
    _last_tokens.clear();
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
    
    struct llama_sampler * smpl = ButlerMakeSampler(temperature, llama_vocab_n_tokens(_vocab));
    for (size_t i = std::max(0, (int)_last_tokens.size() - 256); i < _last_tokens.size(); i++) {
        llama_sampler_accept(smpl, _last_tokens[i]);
    }
    
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
        // Truncating would silently cut the END of the system prompt, producing a cache that
        // never matches the real prompt. Refuse instead; the analyzer/PromptBuilder budgets prevent this.
        if (error) *error = [NSError errorWithDomain:@"Llama" code:7 userInfo:@{NSLocalizedDescriptionKey: @"Project context is too large for the model context window"}];
        return NO;
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
    
    // A failed load may leave the context partially written; reset so nothing stale is trusted.
    llama_memory_t mem = llama_get_memory(_ctx);
    if (mem) llama_memory_clear(mem, true);
    _last_tokens.clear();
    if (error) *error = [NSError errorWithDomain:@"Llama" code:6 userInfo:@{NSLocalizedDescriptionKey: @"Failed to load binary state"}];
    return NO;
}

@end
