#import "WhisperWrapper.h"
#import "whisper.h"
#import <vector>
#import <string>

@interface WhisperWrapper () {
    struct whisper_context *ctx;
    BOOL isCancelled;
}
@end

@implementation WhisperWrapper

- (nullable instancetype)initWithModelPath:(NSString *)modelPath {
    self = [super init];
    if (self) {
        isCancelled = NO;
        struct whisper_context_params cparams = whisper_context_default_params();
        cparams.use_gpu = true; // Use Metal GPU acceleration
        
        ctx = whisper_init_from_file_with_params([modelPath UTF8String], cparams);
        if (ctx == nullptr) {
            NSLog(@"[WhisperWrapper] Failed to initialize whisper context from model: %@", modelPath);
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    if (ctx) {
        whisper_free(ctx);
        ctx = nullptr;
    }
}

- (nullable NSString *)transcribeAudio:(const float *)samples count:(NSInteger)count {
    if (ctx == nullptr) {
        return nil;
    }
    
    struct whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wparams.print_progress   = false;
    wparams.print_special    = false;
    wparams.print_realtime   = false;
    wparams.print_timestamps = false;
    wparams.translate        = false;
    wparams.language         = "en";
    wparams.n_threads        = (int)MIN(4, [[NSProcessInfo processInfo] activeProcessorCount]);
    wparams.single_segment   = true;
    
    wparams.abort_callback = [](void *user_data) -> bool {
        return *(BOOL *)user_data;
    };
    wparams.abort_callback_user_data = &isCancelled;
    
    // Check for cancellation before processing
    if (isCancelled) {
        isCancelled = NO;
        return nil;
    }
    
    int ret = whisper_full(ctx, wparams, samples, (int)count);
    if (ret != 0) {
        NSLog(@"[WhisperWrapper] Failed to process audio");
        return nil;
    }
    
    // Check for cancellation after processing
    if (isCancelled) {
        isCancelled = NO;
        return nil;
    }
    
    const int n_segments = whisper_full_n_segments(ctx);
    std::string result = "";
    
    for (int i = 0; i < n_segments; ++i) {
        const char * text = whisper_full_get_segment_text(ctx, i);
        if (text) {
            result += text;
        }
    }
    
    return [NSString stringWithUTF8String:result.c_str()];
}

- (void)cancelTranscription {
    isCancelled = YES;
}

@end
