#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LlamaWrapper : NSObject

- (BOOL)loadModel:(NSString *)path contextSize:(int32_t)contextSize error:(NSError **)error;
- (void)unload;
- (void)generateStreaming:(NSString *)prompt temperature:(float)temperature maxTokens:(int32_t)maxTokens onToken:(void (^)(NSString *))onToken;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
