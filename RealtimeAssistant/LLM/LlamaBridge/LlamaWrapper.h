#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LlamaWrapper : NSObject

- (void)loadModel:(NSString *)path contextSize:(int32_t)contextSize;
- (void)unload;
- (void)generateStreaming:(NSString *)prompt temperature:(float)temperature maxTokens:(int32_t)maxTokens callback:(void (^)(NSString *))callback;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
