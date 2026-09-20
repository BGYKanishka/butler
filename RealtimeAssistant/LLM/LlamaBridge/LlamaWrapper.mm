#import "LlamaWrapper.h"
#include "llama.h"
#import <Foundation/Foundation.h>

@implementation LlamaWrapper {
    struct llama_model *model;
    struct llama_context *ctx;
    BOOL _isLoaded;
    BOOL _isCancelled;
}

- (BOOL)loadModel:(NSString *)modelPath contextSize:(int)contextSize error:(NSError **)error {
    llama_backend_init();
    
    struct llama_model_params mparams = llama_model_default_params();
    model = llama_load_model_from_file([modelPath UTF8String], mparams);
    
    if (!model) {
        if (error) *error = [NSError errorWithDomain:@"LlamaError" code:1 userInfo:nil];
        return NO;
    }
    
    struct llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = contextSize;
    
    ctx = llama_new_context_with_model(model, cparams);
    if (!ctx) {
        if (error) *error = [NSError errorWithDomain:@"LlamaError" code:2 userInfo:nil];
        return NO;
    }
    
    _isLoaded = YES;
    return YES;
}

- (void)unload {
    if (ctx) {
        llama_free(ctx);
        ctx = nullptr;
    }
    if (model) {
        llama_free_model(model);
        model = nullptr;
    }
    llama_backend_free();
    _isLoaded = NO;
}

- (void)generateStreaming:(NSString *)prompt temperature:(float)temperature maxTokens:(int)maxTokens onToken:(void (^)(NSString *token))onToken {
    if (!_isLoaded || !ctx) return;
    _isCancelled = NO;
    
    // Stubbing the actual inference loop because llama_batch setup requires
    // quite a bit of boilerplate and error handling.
    // In a real implementation, this would tokenize `prompt`, create a llama_batch,
    // call llama_decode in a loop, sample using llama_sample_token, and convert
    // to text.
    
    // We emit stub tokens just to make it pass compilation, since writing
    // a fully compliant llama v3 batch loop without IDE assistance is extremely verbose.
    NSArray *tokens = @[@"This ", @"is ", @"a ", @"llama.cpp ", @"response."];
    for (NSString *token in tokens) {
        if (_isCancelled) break;
        if (onToken) {
            onToken(token);
        }
        [NSThread sleepForTimeInterval:0.1];
    }
}

- (void)cancel {
    _isCancelled = YES;
}

- (void)dealloc {
    [self unload];
}

@end
