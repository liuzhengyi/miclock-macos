#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BOOL MLAnalyticsConsentEnabled(NSUserDefaults *defaults);
FOUNDATION_EXPORT void MLAnalyticsSetConsent(NSUserDefaults *defaults, BOOL enabled);
FOUNDATION_EXPORT NSDictionary * _Nullable MLAnalyticsBuildPayload(NSString *event, NSString *installID,
    NSString *eventID, NSString *version, NSInteger build, NSDate *occurredAt);
FOUNDATION_EXPORT void MLAnalyticsSetEnabled(BOOL enabled);
FOUNDATION_EXPORT void MLAnalyticsRecordEvent(NSString *event);
FOUNDATION_EXPORT void MLAnalyticsRecordLockActivity(BOOL isHealthyLockedInput);
FOUNDATION_EXPORT NSArray<NSString *> *MLAnalyticsPendingLockEvents(NSUserDefaults *defaults, BOOL matches, NSDate *date);
FOUNDATION_EXPORT void MLAnalyticsMarkLockEventAcknowledged(NSUserDefaults *defaults, NSString *event, NSDate *date);
FOUNDATION_EXPORT BOOL MLAnalyticsValidateReceipt(NSData *data, NSInteger status, NSString *eventID);
NS_ASSUME_NONNULL_END
