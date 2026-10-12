#import "MLFeedback.h"
#import "MLAudio.h"
#import "MLState.h"
#import "MLAnalytics.h"
#import <sys/sysctl.h>
#import <math.h>
#import <string.h>

static NSString * const MLFeedbackErrorDomain = @"io.github.liuzhengyi.miclock.feedback";
static NSMutableArray<NSDictionary *> *MLFeedbackEvents;

static NSString *MLF(NSString *key) { return NSLocalizedString(key, nil); }
static NSError *MLFeedbackError(NSString *message) {
    return [NSError errorWithDomain:MLFeedbackErrorDomain code:1
        userInfo:@{NSLocalizedDescriptionKey: message}];
}
static NSString *MLSystemValue(const char *key) {
    size_t size = 0;
    if (sysctlbyname(key, NULL, &size, NULL, 0) != 0 || size == 0 || size > 1024) return @"unknown";
    NSMutableData *data = [NSMutableData dataWithLength:size];
    if (sysctlbyname(key, data.mutableBytes, &size, NULL, 0) != 0) return @"unknown";
    NSString *value = [[NSString alloc] initWithBytes:data.bytes
        length:strnlen(data.bytes, data.length) encoding:NSUTF8StringEncoding];
    return value != nil ? value : @"unknown";
}
static BOOL MLFeedbackBoolean(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}
static BOOL MLFeedbackNumber(id value) {
    return [value isKindOfClass:NSNumber.class] && !MLFeedbackBoolean(value) && isfinite([value doubleValue]);
}
static BOOL MLFeedbackUUIDIsV4(NSString *value) {
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
    NSString *canonical = uuid.UUIDString.lowercaseString;
    return canonical.length == 36 && [canonical characterAtIndex:14] == '4'
        && [@"89ab" rangeOfString:[canonical substringWithRange:NSMakeRange(19, 1)]].location != NSNotFound;
}
static BOOL MLFeedbackMatches(id value, NSString *pattern) {
    return [value isKindOfClass:NSString.class] && [value length] <= 160
        && [[NSPredicate predicateWithFormat:@"SELF MATCHES %@", pattern] evaluateWithObject:value];
}
static NSDictionary *MLFeedbackFilterDiagnostics(NSDictionary *source) {
    if (![source isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSDictionary *patterns = @{@"appVersion":@"[0-9]+(\\.[0-9]+){1,3}|unknown",
        @"appBuild":@"[0-9]{1,10}|unknown", @"osVersion":@"[0-9]+(\\.[0-9]+){1,3}|unknown",
        @"osBuild":@"[A-Za-z0-9]{1,30}|unknown", @"hardwareModel":@"[A-Za-z0-9,_-]{1,64}|unknown"};
    for (NSString *key in patterns) if (MLFeedbackMatches(source[key], patterns[key])) result[key] = source[key];
    for (NSString *key in @[@"lockEnabled", @"targetPresent", @"currentMatchesTarget"])
        if (MLFeedbackBoolean(source[key])) result[key] = source[key];
    if ([@[@"arm64", @"x86_64", @"i386", @"unknown"] containsObject:source[@"architecture"]])
        result[@"architecture"] = source[@"architecture"];
    if ([@[@"locked", @"waiting", @"unavailable", @"error", @"paused", @"backoff", @"conflict",
        @"healthy", @"corrected", @"needsTarget", @"notRunning", @"disabled", @"target-missing", @"unknown"]
        containsObject:source[@"healthStatus"]]) result[@"healthStatus"] = source[@"healthStatus"];
    id memory = source[@"memoryBytes"];
    if (MLFeedbackNumber(memory) && [memory doubleValue] >= 0
        && [memory doubleValue] <= 1099511627776.0) result[@"memoryBytes"] = memory;
    NSMutableArray *inputs = [NSMutableArray array];
    if ([source[@"inputs"] isKindOfClass:NSArray.class]) {
        for (id entry in source[@"inputs"]) {
            if (![entry isKindOfClass:NSDictionary.class] || inputs.count >= 16) continue;
            NSMutableDictionary *input = [NSMutableDictionary dictionary];
            id kind = entry[@"kind"];
            if (MLFeedbackNumber(kind) && [kind integerValue] >= 0 && [kind integerValue] <= 4
                && [kind doubleValue] == [kind integerValue]) input[@"kind"] = kind;
            if ([@[@"Built-in", @"Bluetooth", @"External", @"Virtual", @"Other"] containsObject:entry[@"transport"]])
                input[@"transport"] = entry[@"transport"];
            for (NSString *key in @[@"alive", @"isTarget", @"isCurrent"])
                if (MLFeedbackBoolean(entry[key])) input[key] = entry[key];
            id rate = entry[@"nominalSampleRate"];
            if (MLFeedbackNumber(rate) && [rate doubleValue] > 0
                && [rate doubleValue] <= 384000) input[@"nominalSampleRate"] = rate;
            id channels = entry[@"inputChannels"];
            if (MLFeedbackNumber(channels) && [channels integerValue] >= 0 && [channels integerValue] <= 1024
                && [channels doubleValue] == [channels integerValue]) input[@"inputChannels"] = channels;
            if (input.count > 0) [inputs addObject:input];
        }
    }
    result[@"inputs"] = inputs;
    NSMutableArray *events = [NSMutableArray array];
    NSArray *allowed = @[@"launch", @"toggle-lock", @"select-target", @"switch-input", @"listener-failed",
        @"correction-backoff", @"correction-resumed", @"feedback-submitted", @"feedback-failed"];
    if ([source[@"recentEvents"] isKindOfClass:NSArray.class]) {
        for (id event in source[@"recentEvents"]) {
            if (![event isKindOfClass:NSDictionary.class] || events.count >= 30) continue;
            id name = event[@"event"];
            id seconds = event[@"secondsAgo"];
            if ([allowed containsObject:name] && MLFeedbackNumber(seconds)
                && [seconds doubleValue] >= 0 && [seconds doubleValue] <= 86400)
                [events addObject:@{@"event":name, @"secondsAgo":seconds}];
        }
    }
    result[@"recentEvents"] = events;
    return result;
}

void MLFeedbackRecordEvent(NSString *event) {
    // Fixed event names only: no device names, paths or free-form log text.
    NSSet *allowed = [NSSet setWithArray:@[@"launch", @"toggle-lock", @"select-target",
        @"switch-input", @"listener-failed", @"correction-backoff", @"correction-resumed",
        @"feedback-submitted", @"feedback-failed"]];
    if (![allowed containsObject:event]) return;
    @synchronized (MLFeedbackWindowController.class) {
        if (MLFeedbackEvents == nil) MLFeedbackEvents = [NSMutableArray array];
        [MLFeedbackEvents addObject:@{@"event":event, @"time":@([NSDate.date timeIntervalSince1970])}];
        if (MLFeedbackEvents.count > 30) [MLFeedbackEvents removeObjectAtIndex:0];
    }
}

NSDictionary *MLFeedbackDiagnostics(void) {
    NSDictionary *config = MLLoadConfiguration();
    NSDictionary *health = MLLoadHealth();
    MLAudioDevice *current = MLAudioCurrentInput(NULL);
    NSString *target = [config[MLConfigTargetUIDKey] isKindOfClass:NSString.class]
        ? config[MLConfigTargetUIDKey] : @"";
    NSArray<MLAudioDevice *> *devices = MLAudioInputDevices(NULL);
    NSMutableArray *inputs = [NSMutableArray array];
    BOOL targetPresent = NO;
    for (MLAudioDevice *device in devices) {
        BOOL isTarget = target.length > 0 && [device.uid isEqualToString:target];
        targetPresent |= isTarget;
        NSMutableDictionary *input = [@{@"kind":@(device.kind),
            @"transport":device.transportLabel != nil ? device.transportLabel : @"Other", @"alive":@(device.alive),
            @"isTarget":@(isTarget), @"isCurrent":@([device.uid isEqualToString:current.uid])} mutableCopy];
        AudioObjectPropertyAddress rateAddress = {kAudioDevicePropertyNominalSampleRate,
            kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        Float64 rate = 0;
        UInt32 rateSize = sizeof(rate);
        if (AudioObjectGetPropertyData(device.deviceID, &rateAddress, 0, NULL, &rateSize, &rate) == noErr
            && isfinite(rate) && rate > 0) input[@"nominalSampleRate"] = @(rate);
        AudioObjectPropertyAddress streamAddress = {kAudioDevicePropertyStreamConfiguration,
            kAudioDevicePropertyScopeInput, kAudioObjectPropertyElementMain};
        UInt32 streamSize = 0;
        if (AudioObjectGetPropertyDataSize(device.deviceID, &streamAddress, 0, NULL, &streamSize) == noErr
            && streamSize >= sizeof(AudioBufferList) && streamSize < 65536) {
            NSMutableData *streamData = [NSMutableData dataWithLength:streamSize];
            if (AudioObjectGetPropertyData(device.deviceID, &streamAddress, 0, NULL,
                &streamSize, streamData.mutableBytes) == noErr) {
                AudioBufferList *list = streamData.mutableBytes;
                NSUInteger maxBuffers = (streamData.length - offsetof(AudioBufferList, mBuffers)) / sizeof(AudioBuffer);
                if (list->mNumberBuffers <= maxBuffers) {
                    NSUInteger channels = 0;
                    for (UInt32 i = 0; i < list->mNumberBuffers; i++) channels += list->mBuffers[i].mNumberChannels;
                    input[@"inputChannels"] = @(channels);
                }
            }
        }
        [inputs addObject:input];
    }
    BOOL enabled = [config[MLConfigEnabledKey] boolValue];
    NSString *status = [health[@"status"] isKindOfClass:NSString.class] ? health[@"status"] : @"unknown";
    NSSet *statuses = [NSSet setWithArray:@[@"locked", @"waiting", @"unavailable", @"error",
        @"paused", @"backoff", @"conflict", @"healthy", @"corrected", @"needsTarget", @"notRunning",
        @"disabled", @"target-missing", @"unknown"]];
    if (![statuses containsObject:status]) status = @"unknown";
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSArray *events;
    @synchronized (MLFeedbackWindowController.class) { events = MLFeedbackEvents != nil ? [MLFeedbackEvents copy] : @[]; }
    NSMutableArray *relativeEvents = [NSMutableArray array];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    for (NSDictionary *event in events) {
        NSTimeInterval age = now - [event[@"time"] doubleValue];
        if (age >= 0 && age <= 86400) [relativeEvents addObject:@{@"event":event[@"event"], @"secondsAgo":@(age)}];
    }
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    return MLFeedbackFilterDiagnostics(@{@"appVersion":info[@"CFBundleShortVersionString"] != nil ? info[@"CFBundleShortVersionString"] : @"unknown",
        @"appBuild":info[@"CFBundleVersion"] != nil ? info[@"CFBundleVersion"] : @"unknown",
        @"osVersion":[NSString stringWithFormat:@"%ld.%ld.%ld", (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion],
        @"osBuild":MLSystemValue("kern.osversion"), @"architecture":MLSystemValue("hw.machine"),
        @"hardwareModel":MLSystemValue("hw.model"),
        @"memoryBytes":@(NSProcessInfo.processInfo.physicalMemory), @"lockEnabled":@(enabled),
        @"healthStatus":enabled ? status : @"paused", @"targetPresent":@(targetPresent),
        @"currentMatchesTarget":@(target.length > 0 && [current.uid isEqualToString:target]),
        @"inputs":inputs, @"recentEvents":relativeEvents});
}

NSDictionary *MLFeedbackBuildPayload(NSString *description, NSString *requestID,
    NSDictionary *diagnostics, NSError **error) {
    NSString *text = [description stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:requestID];
    BOOL uuidV4 = MLFeedbackUUIDIsV4(requestID);
    if (text.length < 1 || text.length > 4000 || !uuidV4) {
        if (error != NULL) *error = MLFeedbackError(MLF(@"Please describe the issue in 1 to 4000 characters."));
        return nil;
    }
    NSMutableDictionary *payload = [@{@"schema":@1, @"clientRequestId":uuid.UUIDString.lowercaseString,
        @"description":text} mutableCopy];
    if (diagnostics != nil) payload[@"diagnostics"] = MLFeedbackFilterDiagnostics(diagnostics);
    if (![NSJSONSerialization isValidJSONObject:payload]) {
        if (error != NULL) *error = MLFeedbackError(MLF(@"The diagnostic report is invalid. Please try without diagnostics."));
        return nil;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
    if (data == nil || data.length > 65536) {
        if (error != NULL && *error == nil) *error = MLFeedbackError(MLF(@"The report is too large. Please shorten the description."));
        return nil;
    }
    return payload;
}

NSDictionary *MLFeedbackValidateResponse(NSData *data, NSInteger status,
    NSString *requestID, NSError **error) {
    if (status < 200 || status > 202 || data.length > 16384) {
        if (error != NULL) *error = MLFeedbackError(MLF(@"Could not send the report. Your description is saved; try again later."));
        return nil;
    }
    id result = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![result isKindOfClass:NSDictionary.class]) result = nil;
    id accepted = result[@"accepted"];
    NSString *receipt = [result[@"receiptId"] isKindOfClass:NSString.class] ? result[@"receiptId"] : @"";
    NSString *returnedID = [result[@"clientRequestId"] isKindOfClass:NSString.class] ? result[@"clientRequestId"] : @"";
    NSString *storage = [result[@"storageStatus"] isKindOfClass:NSString.class] ? result[@"storageStatus"] : @"";
    NSCharacterSet *invalidReceiptCharacters = [[NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"] invertedSet];
    BOOL valid = MLFeedbackUUIDIsV4(requestID) && MLFeedbackBoolean(accepted) && [accepted boolValue]
        && [returnedID.lowercaseString isEqualToString:requestID.lowercaseString]
        && receipt.length > 0 && receipt.length <= 64
        && [receipt rangeOfCharacterFromSet:invalidReceiptCharacters].location == NSNotFound
        && [@[@"received", @"feishu_synced"] containsObject:storage];
    if (!valid) {
        if (error != NULL) *error = MLFeedbackError(MLF(@"The server did not confirm receipt. Your description is saved; try again later."));
        return nil;
    }
    return @{@"accepted":@YES, @"receiptId":receipt, @"clientRequestId":returnedID.lowercaseString,
        @"storageStatus":storage};
}

static BOOL MLFeedbackSaveFile(NSString *name, NSDictionary *value, NSError **error) {
    NSURL *directory = MLSupportDirectoryURL();
    NSFileManager *manager = NSFileManager.defaultManager;
    NSDictionary *attributes = [manager attributesOfItemAtPath:directory.path error:NULL];
    if (attributes != nil && ![attributes[NSFileType] isEqualToString:NSFileTypeDirectory]) return NO;
    if (![manager createDirectoryAtURL:directory withIntermediateDirectories:YES
        attributes:@{NSFilePosixPermissions:@0700} error:error]) return NO;
    NSURL *url = [directory URLByAppendingPathComponent:name];
    attributes = [manager attributesOfItemAtPath:url.path error:NULL];
    if (attributes != nil && ![attributes[NSFileType] isEqualToString:NSFileTypeRegular]) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:error];
    if (data == nil || ![data writeToURL:url options:NSDataWritingAtomic error:error]) return NO;
    return [manager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:url.path error:error];
}

@interface MLFeedbackWindowController () <NSTextViewDelegate, NSURLSessionTaskDelegate>
@property(nonatomic, strong) NSTextView *descriptionView;
@property(nonatomic, strong) NSButton *includeDiagnostics;
@property(nonatomic, strong) NSButton *sendButton;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSProgressIndicator *progress;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSDictionary *pendingPayload;
@property(nonatomic, copy) NSString *pendingID;
@property(nonatomic) BOOL sending;
@property(nonatomic) BOOL sent;
@end

@implementation MLFeedbackWindowController
- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 390)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:window];
    if (self == nil) return nil;
    window.title = MLF(@"Report an Issue");
    window.releasedWhenClosed = NO;
    [window center];
    NSView *content = window.contentView;
    NSTextField *intro = [NSTextField wrappingLabelWithString:MLF(@"Describe what happened. You can use your voice input method here.")];
    intro.frame = NSMakeRect(24, 328, 512, 38);
    [content addSubview:intro];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(24, 145, 512, 175)];
    scroll.borderType = NSBezelBorder;
    scroll.hasVerticalScroller = YES;
    self.descriptionView = [[NSTextView alloc] initWithFrame:scroll.bounds];
    self.descriptionView.richText = NO;
    self.descriptionView.font = [NSFont systemFontOfSize:14];
    self.descriptionView.textContainerInset = NSMakeSize(10, 10);
    self.descriptionView.delegate = self;
    [self.descriptionView setAccessibilityLabel:MLF(@"Problem description")];
    scroll.documentView = self.descriptionView;
    [content addSubview:scroll];
    self.includeDiagnostics = [NSButton checkboxWithTitle:MLF(@"Include system and MicLock diagnostics")
        target:self action:@selector(diagnosticsChanged:)];
    self.includeDiagnostics.frame = NSMakeRect(24, 112, 390, 24);
    self.includeDiagnostics.state = NSControlStateValueOn;
    [content addSubview:self.includeDiagnostics];
    NSButton *view = [NSButton buttonWithTitle:MLF(@"View diagnostics") target:self action:@selector(viewDiagnostics:)];
    view.frame = NSMakeRect(412, 111, 124, 26);
    [content addSubview:view];
    NSTextField *privacy = [NSTextField wrappingLabelWithString:MLF(@"Diagnostics include versions and microphone status. No audio, input text, account credentials or device names are collected.")];
    privacy.font = [NSFont systemFontOfSize:11];
    privacy.textColor = NSColor.secondaryLabelColor;
    privacy.frame = NSMakeRect(24, 68, 512, 37);
    [content addSubview:privacy];
    self.statusLabel = [NSTextField wrappingLabelWithString:@""];
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.frame = NSMakeRect(24, 14, 365, 48);
    [content addSubview:self.statusLabel];
    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(390, 27, 16, 16)];
    self.progress.style = NSProgressIndicatorStyleSpinning;
    self.progress.displayedWhenStopped = NO;
    [content addSubview:self.progress];
    self.sendButton = [NSButton buttonWithTitle:MLF(@"Send report") target:self action:@selector(send:)];
    self.sendButton.frame = NSMakeRect(420, 22, 116, 32);
    self.sendButton.bezelStyle = NSBezelStyleRounded;
    self.sendButton.keyEquivalent = @"\r";
    self.sendButton.enabled = NO;
    [content addSubview:self.sendButton];
    NSURL *draftURL = [MLSupportDirectoryURL() URLByAppendingPathComponent:@"feedback-draft.json"];
    NSDictionary *draftAttributes = [NSFileManager.defaultManager attributesOfItemAtPath:draftURL.path error:NULL];
    NSData *draft = [draftAttributes[NSFileType] isEqualToString:NSFileTypeRegular]
        && [draftAttributes[NSFileSize] unsignedLongLongValue] <= 65536 ? [NSData dataWithContentsOfURL:draftURL] : nil;
    if (draft != nil && draft.length <= 65536) {
        id payload = [NSJSONSerialization JSONObjectWithData:draft options:0 error:NULL];
        if ([payload isKindOfClass:NSDictionary.class] && [payload[@"description"] isKindOfClass:NSString.class]
            && [payload[@"clientRequestId"] isKindOfClass:NSString.class]) {
            self.pendingPayload = MLFeedbackBuildPayload(payload[@"description"], payload[@"clientRequestId"],
                [payload[@"diagnostics"] isKindOfClass:NSDictionary.class] ? payload[@"diagnostics"] : nil, NULL);
            self.pendingID = self.pendingPayload[@"clientRequestId"];
            if (self.pendingPayload == nil) return self;
            self.descriptionView.string = payload[@"description"];
            self.includeDiagnostics.state = payload[@"diagnostics"] != nil ? NSControlStateValueOn : NSControlStateValueOff;
            self.statusLabel.stringValue = MLF(@"Your previous unsent report is ready to retry.");
            self.sendButton.enabled = YES;
        }
    }
    return self;
}
- (void)showWindow:(id)sender {
    [super showWindow:sender];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeFirstResponder:self.descriptionView];
}
- (void)textDidChange:(NSNotification *)notification {
    (void)notification;
    if (self.sending) return;
    self.pendingPayload = nil;
    self.pendingID = nil;
    self.sent = NO;
    self.statusLabel.stringValue = @"";
    self.sendButton.enabled = [self.descriptionView.string stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
}
- (void)diagnosticsChanged:(id)sender {
    (void)sender;
    [self textDidChange:[NSNotification notificationWithName:NSTextDidChangeNotification object:self.descriptionView]];
}
- (void)viewDiagnostics:(id)sender {
    (void)sender;
    NSDictionary *diagnostics = self.pendingPayload[@"diagnostics"] != nil
        ? self.pendingPayload[@"diagnostics"] : MLFeedbackDiagnostics();
    NSData *data = [NSJSONSerialization dataWithJSONObject:diagnostics options:NSJSONWritingPrettyPrinted error:NULL];
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text == nil) text = @"";
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = MLF(@"Diagnostics preview");
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 480, 280)];
    scroll.hasVerticalScroller = YES;
    NSTextView *view = [[NSTextView alloc] initWithFrame:scroll.bounds];
    view.string = text;
    view.editable = NO;
    view.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    scroll.documentView = view;
    alert.accessoryView = scroll;
    [alert addButtonWithTitle:MLF(@"Done")];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}
- (void)send:(id)sender {
    (void)sender;
    if (self.sending || self.sent) return;
    NSString *endpoint = NSBundle.mainBundle.infoDictionary[@"MLFeedbackEndpoint"];
    NSURL *url = [endpoint isKindOfClass:NSString.class] ? [NSURL URLWithString:endpoint] : nil;
    if (![url.scheme isEqualToString:@"https"] || url.host.length == 0 || url.user != nil || url.password != nil) {
        self.statusLabel.stringValue = MLF(@"The feedback service is not available in this build. Please check for an update.");
        return;
    }
    NSError *error = nil;
    if (self.pendingPayload == nil) {
        self.pendingID = NSUUID.UUID.UUIDString.lowercaseString;
        self.pendingPayload = MLFeedbackBuildPayload(self.descriptionView.string, self.pendingID,
            self.includeDiagnostics.state == NSControlStateValueOn ? MLFeedbackDiagnostics() : nil, &error);
    }
    if (self.pendingPayload == nil) { self.statusLabel.stringValue = error.localizedDescription; return; }
    if (!MLFeedbackSaveFile(@"feedback-draft.json", self.pendingPayload, &error)) {
        self.statusLabel.stringValue = MLF(@"Could not save the report locally. Please copy your description and try again.");
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 30;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:self.pendingPayload options:0 error:&error];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:self.pendingID forHTTPHeaderField:@"Idempotency-Key"];
    // The official Miaoda runtime uses double-submit CSRF. This random value is
    // not an authorization credential; the service performs its own validation.
    [request setValue:self.pendingID forHTTPHeaderField:@"X-Suda-Csrf-Token"];
    [request setValue:[@"suda-csrf-token=" stringByAppendingString:self.pendingID]
        forHTTPHeaderField:@"Cookie"];
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest = 30;
    config.timeoutIntervalForResource = 45;
    config.HTTPShouldSetCookies = NO;
    self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    self.sending = YES;
    self.descriptionView.editable = NO;
    self.includeDiagnostics.enabled = NO;
    self.sendButton.enabled = NO;
    self.statusLabel.stringValue = MLF(@"Sending…");
    [self.progress startAnimation:nil];
    NSString *requestID = self.pendingID;
    __weak MLFeedbackWindowController *weakSelf = self;
    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NSError *responseError = networkError;
        NSDictionary *receipt = networkError == nil
            ? MLFeedbackValidateResponse(data != nil ? data : NSData.data, status, requestID, &responseError) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            MLFeedbackWindowController *strongSelf = weakSelf;
            if (strongSelf == nil) return;
            strongSelf.sending = NO;
            strongSelf.descriptionView.editable = YES;
            strongSelf.includeDiagnostics.enabled = YES;
            [strongSelf.progress stopAnimation:nil];
            if (receipt != nil) {
                NSMutableDictionary *saved = [strongSelf.pendingPayload mutableCopy];
                saved[@"receipt"] = receipt;
                if (MLFeedbackSaveFile(@"feedback-latest.json", saved, NULL)) {
                    NSURL *draft = [MLSupportDirectoryURL() URLByAppendingPathComponent:@"feedback-draft.json"];
                    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:draft.path error:NULL];
                    if ([attributes[NSFileType] isEqualToString:NSFileTypeRegular])
                        [NSFileManager.defaultManager removeItemAtURL:draft error:NULL];
                }
                strongSelf.sent = YES;
                NSString *format = MLF(@"Report received: %@. Thank you.");
                strongSelf.statusLabel.stringValue = [NSString stringWithFormat:format, receipt[@"receiptId"]];
                MLFeedbackRecordEvent(@"feedback-submitted");
                MLAnalyticsRecordEvent(@"feedback_submitted");
            } else {
                strongSelf.sendButton.enabled = YES;
                strongSelf.statusLabel.stringValue = MLF(@"Could not send the report. Your description is saved; try again later.");
                MLFeedbackRecordEvent(@"feedback-failed");
            }
            [strongSelf.session finishTasksAndInvalidate];
            strongSelf.session = nil;
        });
    }] resume];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    (void)session; (void)task; (void)response; (void)request;
    // Never forward the user's report to a URL supplied by a redirect.
    completionHandler(nil);
}
@end
