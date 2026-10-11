#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void MLFeedbackRecordEvent(NSString *event);
FOUNDATION_EXPORT NSDictionary *MLFeedbackDiagnostics(void);
FOUNDATION_EXPORT NSDictionary * _Nullable MLFeedbackBuildPayload(
    NSString *description, NSString *requestID, NSDictionary * _Nullable diagnostics, NSError **error);
FOUNDATION_EXPORT NSDictionary * _Nullable MLFeedbackValidateResponse(
    NSData *data, NSInteger status, NSString *requestID, NSError **error);

@interface MLFeedbackWindowController : NSWindowController
@end

NS_ASSUME_NONNULL_END
