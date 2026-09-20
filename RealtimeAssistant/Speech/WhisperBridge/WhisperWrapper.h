#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WhisperWrapper : NSObject

- (BOOL)loadModel:(NSString *)modelPath error:(NSError **)error;
- (void)unload;
- (NSString * _Nullable)transcribeSamples:(const float *)samples count:(NSInteger)count;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
