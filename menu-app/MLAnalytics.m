#import "MLAnalytics.h"

static NSString * const MLConsentKey = @"MLAnonymousStatisticsEnabled";
static NSString * const MLInstallIDKey = @"MLAnonymousStatisticsInstallID";
static NSString * const MLConfigurationSeenKey = @"MLAnonymousStatisticsConfigurationSeen";
static NSString * const MLLockDayKey = @"MLAnonymousStatisticsLastLockDay";
static BOOL MLAnalyticsV4ID(NSString *value);

BOOL MLAnalyticsConsentEnabled(NSUserDefaults *defaults) {
    id value = [defaults objectForKey:MLConsentKey];
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()
        && [value boolValue];
}
void MLAnalyticsSetConsent(NSUserDefaults *defaults, BOOL enabled) {
    [defaults setBool:enabled forKey:MLConsentKey];
    if (enabled) {
        if (!MLAnalyticsV4ID([defaults stringForKey:MLInstallIDKey])) {
            [defaults setObject:NSUUID.UUID.UUIDString.lowercaseString forKey:MLInstallIDKey];
        }
    } else {
        for (NSString *key in @[MLInstallIDKey, MLConfigurationSeenKey, MLLockDayKey]) [defaults removeObjectForKey:key];
    }
}
static BOOL MLAnalyticsV4ID(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:
        @"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$" options:0 error:nil];
    return [regex numberOfMatchesInString:value options:0 range:NSMakeRange(0, value.length)] == 1;
}
NSDictionary *MLAnalyticsBuildPayload(NSString *event, NSString *installID, NSString *eventID,
    NSString *version, NSInteger build, NSDate *occurredAt) {
    NSArray *allowed = @[@"app_started", @"configuration_success", @"lock_active", @"update_checked",
        @"feedback_submitted", @"uninstall_requested"];
    if (![allowed containsObject:event] || !MLAnalyticsV4ID(installID) || !MLAnalyticsV4ID(eventID) ||
        ![version isKindOfClass:NSString.class] || version.length > 40 || build <= 0 || build > 1000000000 ||
        ![occurredAt isKindOfClass:NSDate.class]) return nil;
    NSRegularExpression *semver = [NSRegularExpression regularExpressionWithPattern:
        @"^[0-9]{1,9}\\.[0-9]{1,9}\\.[0-9]{1,9}$" options:0 error:nil];
    if ([semver numberOfMatchesInString:version options:0 range:NSMakeRange(0, version.length)] != 1) return nil;
    NSISO8601DateFormatter *date = [[NSISO8601DateFormatter alloc] init];
    return @{@"schema":@1, @"eventId":eventID.lowercaseString, @"installId":installID.lowercaseString, @"event":event,
        @"appVersion":version, @"appBuild":@(build), @"occurredAt":[date stringFromDate:occurredAt]};
}
static NSString *MLAnalyticsUTCDay(NSDate *date) {
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    return [[formatter stringFromDate:date] substringToIndex:10];
}
NSArray<NSString *> *MLAnalyticsPendingLockEvents(NSUserDefaults *defaults, BOOL matches, NSDate *date) {
    if (!matches || !MLAnalyticsConsentEnabled(defaults)) return @[];
    NSMutableArray<NSString *> *events = [NSMutableArray array];
    if (![defaults boolForKey:MLConfigurationSeenKey]) [events addObject:@"configuration_success"];
    if (![[defaults stringForKey:MLLockDayKey] isEqualToString:MLAnalyticsUTCDay(date)]) [events addObject:@"lock_active"];
    return events;
}
void MLAnalyticsMarkLockEventAcknowledged(NSUserDefaults *defaults, NSString *event, NSDate *date) {
    if (!MLAnalyticsConsentEnabled(defaults)) return;
    if ([event isEqualToString:@"configuration_success"]) [defaults setBool:YES forKey:MLConfigurationSeenKey];
    if ([event isEqualToString:@"lock_active"]) [defaults setObject:MLAnalyticsUTCDay(date) forKey:MLLockDayKey];
}
BOOL MLAnalyticsValidateReceipt(NSData *data, NSInteger status, NSString *eventID) {
    if (status != 201 || data.length > 4096 || !MLAnalyticsV4ID(eventID)) return NO;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![value isKindOfClass:NSDictionary.class]) return NO;
    id accepted = value[@"accepted"];
    return [accepted isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)accepted) == CFBooleanGetTypeID()
        && [accepted boolValue] && [value[@"eventId"] isKindOfClass:NSString.class] && MLAnalyticsV4ID(value[@"eventId"]) && [[value[@"eventId"] lowercaseString] isEqualToString:eventID.lowercaseString];
}

@interface MLAnalyticsController : NSObject <NSURLSessionTaskDelegate>
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSMutableSet<NSURLSessionDataTask *> *tasks;
@property(nonatomic, strong) NSMutableSet<NSString *> *pendingLockEvents;
@end
@implementation MLAnalyticsController
- (instancetype)init {
    self = [super init];
    if (self != nil) {
        self.queue = dispatch_queue_create("io.github.liuzhengyi.miclock.analytics", DISPATCH_QUEUE_SERIAL);
        self.tasks = [NSMutableSet set];
        self.pendingLockEvents = [NSMutableSet set];
        // Session itself does not send any request. Tasks exist only after an
        // explicit consent check on the serial queue below.
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.URLCache = nil; configuration.HTTPCookieStorage = nil;
        configuration.HTTPShouldSetCookies = NO;
        configuration.timeoutIntervalForRequest = 12;
        configuration.timeoutIntervalForResource = 15;
        self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    }
    return self;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:
    (NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:
    (void (^)(NSURLRequest * _Nullable))completionHandler {
    (void)session; (void)task; (void)response; (void)request;
    completionHandler(nil); // Never forward this installation ID to a redirect.
}
- (BOOL)sendEvent:(NSString *)event atDate:(NSDate *)date {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (!MLAnalyticsConsentEnabled(defaults)) return NO;
    NSString *endpoint = NSBundle.mainBundle.infoDictionary[@"MLAnalyticsEndpoint"];
    NSURL *url = [endpoint isKindOfClass:NSString.class] ? [NSURL URLWithString:endpoint] : nil;
    if (![url.scheme isEqualToString:@"https"] ||
        ![url.host.lowercaseString isEqualToString:@"ecnkfnba0c1r.feishuapp.com"] ||
        ![url.path hasPrefix:@"/app/"] || ![url.path hasSuffix:@"/api/analytics/events"] ||
        url.user.length > 0 || url.password.length > 0 || url.query.length > 0 || url.fragment.length > 0 ||
        (url.port != nil && url.port.integerValue != 443)) return NO;
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    BOOL lockEvent = [event isEqualToString:@"configuration_success"] || [event isEqualToString:@"lock_active"];
    NSString *pendingKey = [NSString stringWithFormat:@"%@|%@|%@",[defaults stringForKey:MLInstallIDKey],event,MLAnalyticsUTCDay(date)];
    if (lockEvent && [self.pendingLockEvents containsObject:pendingKey]) return NO;
    NSDictionary *payload = MLAnalyticsBuildPayload(event, [defaults stringForKey:MLInstallIDKey],
        NSUUID.UUID.UUIDString.lowercaseString, info[@"CFBundleShortVersionString"], [info[@"CFBundleVersion"] integerValue], date);
    if (payload == nil) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (data == nil || data.length > 4096) return NO;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST"; request.HTTPBody = data;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:payload[@"eventId"] forHTTPHeaderField:@"X-Suda-Csrf-Token"];
    [request setValue:[NSString stringWithFormat:@"suda-csrf-token=%@",payload[@"eventId"]] forHTTPHeaderField:@"Cookie"];
    __weak MLAnalyticsController *weakSelf = self;
    // Tasks are capped and never queued on disk or retried in the background.
    if (self.tasks.count >= 8) return NO;
    __block __weak NSURLSessionDataTask *weakTask = nil;
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:
        ^(NSData *result, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        BOOL accepted = error == nil && result != nil && MLAnalyticsValidateReceipt(result,status,payload[@"eventId"]);
        MLAnalyticsController *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        NSURLSessionDataTask *finished = weakTask;
        dispatch_async(strongSelf.queue, ^{
            if (finished != nil) [strongSelf.tasks removeObject:finished];
            [strongSelf.pendingLockEvents removeObject:pendingKey];
            NSUserDefaults *currentDefaults = NSUserDefaults.standardUserDefaults;
            if (lockEvent && accepted && MLAnalyticsConsentEnabled(currentDefaults) &&
                [[[currentDefaults stringForKey:MLInstallIDKey] lowercaseString] isEqualToString:payload[@"installId"]]) {
                MLAnalyticsMarkLockEventAcknowledged(currentDefaults,event,date);
            }
        });
    }];
    weakTask = task;
    [self.tasks addObject:task];
    if (lockEvent) [self.pendingLockEvents addObject:pendingKey];
    [task resume];
    return YES;
}
@end
static MLAnalyticsController *MLAnalyticsShared(void) {
    static MLAnalyticsController *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [[MLAnalyticsController alloc] init]; });
    return controller;
}
void MLAnalyticsSetEnabled(BOOL enabled) {
    MLAnalyticsController *controller = MLAnalyticsShared();
    dispatch_sync(controller.queue, ^{
        if (!enabled) {
            for (NSURLSessionDataTask *task in controller.tasks) [task cancel];
            [controller.tasks removeAllObjects];
            [controller.pendingLockEvents removeAllObjects];
        }
        MLAnalyticsSetConsent(NSUserDefaults.standardUserDefaults, enabled);
        if (enabled) [controller sendEvent:@"app_started" atDate:NSDate.date];
    });
}
void MLAnalyticsRecordEvent(NSString *event) {
    if (!MLAnalyticsConsentEnabled(NSUserDefaults.standardUserDefaults)) return;
    MLAnalyticsController *controller = MLAnalyticsShared();
    dispatch_async(controller.queue, ^{ [controller sendEvent:event atDate:NSDate.date]; });
}
void MLAnalyticsRecordLockActivity(BOOL isHealthyLockedInput) {
    if (!isHealthyLockedInput || !MLAnalyticsConsentEnabled(NSUserDefaults.standardUserDefaults)) return;
    MLAnalyticsController *controller = MLAnalyticsShared();
    dispatch_async(controller.queue, ^{
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        if (!MLAnalyticsConsentEnabled(defaults)) return;
        NSDate *date = NSDate.date;
        for (NSString *event in MLAnalyticsPendingLockEvents(defaults, YES, date)) {
            [controller sendEvent:event atDate:date];
        }
    });
}
