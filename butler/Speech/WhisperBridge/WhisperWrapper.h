#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WhisperWrapper : NSObject

/// Initializes the Whisper engine with a specific model path.
- (nullable instancetype)initWithModelPath:(NSString *)modelPath;

/// Transcribes the provided audio samples. Samples must be 16kHz mono Float32.
/// Returns the transcribed text.
- (nullable NSString *)transcribeAudio:(const float *)samples count:(NSInteger)count;

/// Signals the engine to cancel any ongoing transcription.
- (void)cancelTranscription;

@end

NS_ASSUME_NONNULL_END
