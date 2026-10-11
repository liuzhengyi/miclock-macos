#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Pure policy. The caller supplies monotonic time and schedules a retry when
// retryAfter is positive. Device writes and UI remain outside this class.
@interface MLCorrectionPolicy : NSObject
- (BOOL)mayCorrectAtTime:(NSTimeInterval)time retryAfter:(NSTimeInterval *)retryAfter;
- (void)recordCorrectionAtTime:(NSTimeInterval)time;
- (void)reset;
@end

NS_ASSUME_NONNULL_END
