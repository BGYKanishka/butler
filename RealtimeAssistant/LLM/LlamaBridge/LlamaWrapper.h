#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LlamaWrapper : NSObject

- (BOOL)loadModel:(NSString *)modelPath contextSize:(int)contextSize error:(NSError **)error;
- (void)unload;
- (void)generateStreaming:(NSString *)prompt temperature:(float)temperature maxTokens:(int)maxTokens onToken:(void (^)(NSString *token))onToken;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
