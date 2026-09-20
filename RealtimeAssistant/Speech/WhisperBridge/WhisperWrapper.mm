#import "WhisperWrapper.h"
#import <Foundation/Foundation.h>

#import "WhisperWrapper.h"
#import <Foundation/Foundation.h>
#include "whisper.h"

@implementation WhisperWrapper {
    struct whisper_context *ctx;
}

- (BOOL)loadModel:(NSString *)modelPath error:(NSError **)error {
    struct whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = true;
    
    ctx = whisper_init_from_file_with_params([modelPath UTF8String], cparams);
    if (ctx == nullptr) {
        if (error) {
            *error = [NSError errorWithDomain:@"WhisperError" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to load model"}];
        }
        return NO;
    }
    return YES;
}

- (void)unload {
    if (ctx) {
        whisper_free(ctx);
        ctx = nullptr;
    }
}

- (NSString *)transcribeSamples:(const float *)samples count:(NSInteger)count {
    if (!ctx) return nil;
    
    struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.print_progress = false;
    params.print_special = false;
    params.print_realtime = false;
    params.print_timestamps = false;
    params.language = "en";
    params.n_threads = 4;
    
    if (whisper_full(ctx, params, samples, (int)count) != 0) {
        return nil;
    }
    
    int n_segments = whisper_full_n_segments(ctx);
    NSMutableString *result = [NSMutableString string];
    for (int i = 0; i < n_segments; i++) {
        const char *text = whisper_full_get_segment_text(ctx, i);
        if (text) {
            [result appendString:[NSString stringWithUTF8String:text]];
        }
    }
    return result;
}

- (void)cancel {
    // whisper.cpp does not support async cancel directly via context easily in older API.
}

- (void)dealloc {
    [self unload];
}

@end
