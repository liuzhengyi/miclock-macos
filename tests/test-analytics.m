#import <Foundation/Foundation.h>
#import "MLAnalytics.h"

@interface MLMemoryDefaults : NSUserDefaults
@property(nonatomic, strong) NSMutableDictionary *values;
@end
@implementation MLMemoryDefaults
- (instancetype)init { self = [super init]; if (self != nil) self.values = [NSMutableDictionary dictionary]; return self; }
- (id)objectForKey:(NSString *)key { return self.values[key]; }
- (NSString *)stringForKey:(NSString *)key { return [self.values[key] isKindOfClass:NSString.class] ? self.values[key] : nil; }
- (BOOL)boolForKey:(NSString *)key { return [self.values[key] boolValue]; }
- (void)setObject:(id)value forKey:(NSString *)key { self.values[key] = value; }
- (void)setBool:(BOOL)value forKey:(NSString *)key { self.values[key] = @(value); }
- (void)removeObjectForKey:(NSString *)key { [self.values removeObjectForKey:key]; }
@end
static NSUInteger Count;
static void Assert(BOOL value, NSString *message) {
    Count++;
    if (!value) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
}
int main(void) {
    @autoreleasepool {
        MLMemoryDefaults *defaults = [[MLMemoryDefaults alloc] init];
        Assert(!MLAnalyticsConsentEnabled(defaults), @"statistics disabled by default");
        [defaults setObject:@"yes" forKey:@"MLAnonymousStatisticsEnabled"];
        Assert(!MLAnalyticsConsentEnabled(defaults), @"string consent rejected");
        [defaults setObject:@1 forKey:@"MLAnonymousStatisticsEnabled"];
        Assert(!MLAnalyticsConsentEnabled(defaults), @"numeric consent is not a boolean");
        MLAnalyticsSetConsent(defaults, YES);
        NSString *identifier = [defaults stringForKey:@"MLAnonymousStatisticsInstallID"];
        Assert(MLAnalyticsConsentEnabled(defaults) && identifier.length == 36, @"explicit consent creates random UUID");
        MLAnalyticsSetConsent(defaults, YES);
        Assert([[defaults stringForKey:@"MLAnonymousStatisticsInstallID"] isEqualToString:identifier], @"enabled identifier stable");
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:1791676799];
        NSDate *next = [date dateByAddingTimeInterval:1];
        NSString *eventID = NSUUID.UUID.UUIDString;
        for (NSString *event in @[@"app_started",@"configuration_success",@"lock_active",@"update_checked",@"feedback_submitted",@"uninstall_requested"]) {
            NSDictionary *payload = MLAnalyticsBuildPayload(event,identifier,eventID,@"3.2.0",12,date);
            Assert(payload != nil && payload.count == 7, @"only fixed anonymous schema fields");
            Assert([payload[@"event"] isEqualToString:event] && [payload[@"eventId"] isEqualToString:eventID.lowercaseString], @"event and canonical id preserved");
            Assert(payload[@"hardware"] == nil && payload[@"description"] == nil && payload[@"username"] == nil, @"no hardware or user text");
        }
        Assert(MLAnalyticsBuildPayload(@"voice-text",identifier,eventID,@"3.2.0",12,date)==nil, @"unlisted event rejected");
        Assert(MLAnalyticsBuildPayload(@"app_started",@"user-device-id",eventID,@"3.2.0",12,date)==nil, @"nonrandom device identifier rejected");
        Assert(MLAnalyticsBuildPayload(@"app_started",identifier,@"bad",@"3.2.0",12,date)==nil, @"malformed event id rejected");
        Assert(MLAnalyticsBuildPayload(@"app_started",identifier,eventID,@"3.2.0/private",12,date)==nil, @"arbitrary version text rejected");
        Assert(MLAnalyticsBuildPayload(@"app_started",identifier,eventID,@"3.2.0",0,date)==nil, @"invalid build rejected");
        NSData *receipt = [NSJSONSerialization dataWithJSONObject:@{@"accepted":@YES,@"eventId":eventID} options:0 error:nil];
        Assert(MLAnalyticsValidateReceipt(receipt,201,eventID), @"confirmed matching receipt accepted");
        NSData *lowercaseReceipt = [NSJSONSerialization dataWithJSONObject:@{@"accepted":@YES,@"eventId":eventID.lowercaseString} options:0 error:nil];
        Assert(MLAnalyticsValidateReceipt(lowercaseReceipt,201,eventID.uppercaseString), @"uppercase request matches PostgreSQL lowercase receipt");
        NSDictionary *canonical = MLAnalyticsBuildPayload(@"app_started",identifier.uppercaseString,eventID.uppercaseString,@"3.2.0",12,date);
        Assert([canonical[@"eventId"] isEqualToString:eventID.lowercaseString] && [canonical[@"installId"] isEqualToString:identifier.lowercaseString], @"both outgoing UUIDs canonical lowercase");
        Assert(!MLAnalyticsValidateReceipt(receipt,200,eventID) && !MLAnalyticsValidateReceipt(receipt,429,eventID), @"other statuses cannot mark success");
        Assert(!MLAnalyticsValidateReceipt(receipt,201,NSUUID.UUID.UUIDString), @"old or unrelated event receipt rejected");
        for (id value in @[@NO,@1,@"true",NSNull.null]) {
            NSData *bad = [NSJSONSerialization dataWithJSONObject:@{@"accepted":value,@"eventId":eventID} options:0 error:nil];
            Assert(!MLAnalyticsValidateReceipt(bad,201,eventID), @"receipt accepted must be literal true");
        }
        Assert(MLAnalyticsPendingLockEvents(defaults,NO,date).count==0, @"paused or mismatched input excluded");
        Assert(MLAnalyticsPendingLockEvents(defaults,YES,date).count==2, @"first successful lock emits configuration and active");
        for (NSString *event in MLAnalyticsPendingLockEvents(defaults,YES,date)) MLAnalyticsMarkLockEventAcknowledged(defaults,event,date);
        Assert(MLAnalyticsPendingLockEvents(defaults,YES,date).count==0, @"same day refresh does not repeat");
        NSArray *later = MLAnalyticsPendingLockEvents(defaults,YES,next);
        Assert(later.count==1 && [later.firstObject isEqualToString:@"lock_active"], @"next UTC day records lock activity once");
        MLAnalyticsSetConsent(defaults, NO);
        Assert(!MLAnalyticsConsentEnabled(defaults) && [defaults stringForKey:@"MLAnonymousStatisticsInstallID"]==nil, @"turning off removes random identifier");
        Assert(MLAnalyticsPendingLockEvents(defaults,YES,next).count==0, @"off consent suppresses later activity");
        MLAnalyticsSetConsent(defaults,YES);
        Assert(![[defaults stringForKey:@"MLAnonymousStatisticsInstallID"] isEqualToString:identifier], @"reenabling starts a new anonymous identifier");
        Assert(MLAnalyticsPendingLockEvents(defaults,YES,date).count==2, @"revocation clears observation flags");
        printf("Anonymous analytics model passed (%lu assertions), memory-only defaults; no network or real preferences.\n",(unsigned long)Count);
    }
    return 0;
}
