#import "LlamaWrapper.h"

@implementation LlamaWrapper {
    BOOL _isLoaded;
    BOOL _isCancelled;
}

- (BOOL)loadModel:(NSString *)modelPath contextSize:(int)contextSize error:(NSError **)error {
    _isLoaded = YES;
    return YES;
}

- (void)unload {
    _isLoaded = NO;
}

- (void)generateStreaming:(NSString *)prompt temperature:(float)temperature maxTokens:(int)maxTokens onToken:(void (^)(NSString *token))onToken {
    if (!_isLoaded) return;
    _isCancelled = NO;
    
    NSArray *tokens = @[@"This ", @"is ", @"a ", @"stubbed ", @"response."];
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

@end
