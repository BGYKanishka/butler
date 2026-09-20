#import "WhisperWrapper.h"
#import <Foundation/Foundation.h>

@implementation WhisperWrapper {
    void *ctx;
}

- (BOOL)loadModel:(NSString *)modelPath error:(NSError **)error {
    return YES;
}

- (void)unload {
}

- (NSString *)transcribeSamples:(const float *)samples count:(NSInteger)count {
    return @"Stubbed transcription";
}

- (void)cancel {
}

- (void)dealloc {
}

@end
