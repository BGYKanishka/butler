#import "LlamaWrapper.h"
#import "llama.h"
#include <string>
#include <vector>

@implementation LlamaWrapper {
    struct llama_model *_model;
    struct llama_context *_ctx;
    const struct llama_vocab *_vocab;
    BOOL _isCancelled;
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
    _ctx = llama_new_context_with_model(_model, ctx_params);
    if (!_ctx) {
        llama_free_model(_model);
        _model = NULL;
        _vocab = NULL;
        if (error) *error = [NSError errorWithDomain:@"Llama" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create context"}];
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
        llama_free_model(_model);
        _model = NULL;
        _vocab = NULL;
    }
}

- (void)generateStreaming:(NSString *)prompt temperature:(float)temperature maxTokens:(int)maxTokens onToken:(void (^)(NSString *token))onToken {
    if (!_model || !_ctx || !_vocab) return;
    _isCancelled = NO;
    
    // Tokenize
    std::string prompt_str = [prompt UTF8String];
    std::vector<llama_token> tokens_list(prompt_str.length() + 2); // rough estimate
    
    int n_tokens = llama_tokenize(_vocab, prompt_str.c_str(), prompt_str.length(), tokens_list.data(), tokens_list.size(), true, true);
    if (n_tokens < 0) {
        tokens_list.resize(-n_tokens);
        n_tokens = llama_tokenize(_vocab, prompt_str.c_str(), prompt_str.length(), tokens_list.data(), tokens_list.size(), true, true);
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
    
    while (n_cur <= maxTokens) {
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
    }
    
    llama_sampler_free(smpl);
}

- (void)cancel {
    _isCancelled = YES;
}

@end
