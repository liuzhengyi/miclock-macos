#import <AppKit/AppKit.h>
#import "MLAudio.h"

// Build the real menu graph with fake microphones and a captured browser
// opener. No visible status item, user configuration, audio write, login-item
// registration, network request, clipboard change, or installed app is used.
@interface MLMenuTestWorkspace : NSWorkspace
+ (instancetype)sharedWorkspace;
@property(nonatomic, strong) NSURL *lastOpenedURL;
@property(nonatomic) NSUInteger openCount;
@end
@implementation MLMenuTestWorkspace
+ (instancetype)sharedWorkspace {
    static MLMenuTestWorkspace *workspace;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ workspace = [[MLMenuTestWorkspace alloc] init]; });
    return workspace;
}
- (BOOL)openURL:(NSURL *)url {
    self.lastOpenedURL = url;
    self.openCount++;
    return YES;
}
@end

MLAudioDevice *MLMenuTestCurrentInput(NSError **error);
NSArray<MLAudioDevice *> *MLMenuTestInputDevices(NSError **error);
MLAudioDevice *MLMenuTestDeviceForUID(NSString *uid, NSError **error);
MLAudioDevice *MLMenuTestUniqueBuiltInInput(NSError **error);
BOOL MLMenuTestSetDefaultInputUID(NSString *uid, NSError **error);
void MLMenuTestAnalyticsRecordLockActivity(BOOL matching);
void MLMenuTestAnalyticsRecordEvent(NSString *event);
void MLMenuTestFeedbackRecordEvent(NSString *event);
void MLMenuTestPostConfigurationChanged(void);

#define NSWorkspace MLMenuTestWorkspace
#define MLAudioCurrentInput MLMenuTestCurrentInput
#define MLAudioInputDevices MLMenuTestInputDevices
#define MLAudioDeviceForUID MLMenuTestDeviceForUID
#define MLAudioSetDefaultInputUID MLMenuTestSetDefaultInputUID
#define MLAudioUniqueBuiltInInput MLMenuTestUniqueBuiltInInput
#define MLAnalyticsRecordLockActivity MLMenuTestAnalyticsRecordLockActivity
#define MLAnalyticsRecordEvent MLMenuTestAnalyticsRecordEvent
#define MLFeedbackRecordEvent MLMenuTestFeedbackRecordEvent
#define MLPostConfigurationChanged MLMenuTestPostConfigurationChanged
#define main MLMenuTestEntrypoint
#include "../menu-app/main.m"
#undef main
#undef NSWorkspace
#undef MLAudioCurrentInput
#undef MLAudioInputDevices
#undef MLAudioDeviceForUID
#undef MLAudioSetDefaultInputUID
#undef MLAudioUniqueBuiltInInput
#undef MLAnalyticsRecordLockActivity
#undef MLAnalyticsRecordEvent
#undef MLFeedbackRecordEvent
#undef MLPostConfigurationChanged

static MLAudioDevice *BuiltIn;
static MLAudioDevice *Headset;
static MLAudioDevice *Current;
static NSArray<MLAudioDevice *> *Devices;
static NSUInteger HardwareWriteCount;
static NSUInteger CheckCount;
static BOOL LastRecordedMatching;
MLAudioDevice *MLMenuTestCurrentInput(NSError **error) { (void)error; return Current; }
NSArray<MLAudioDevice *> *MLMenuTestInputDevices(NSError **error) { (void)error; return Devices; }
MLAudioDevice *MLMenuTestDeviceForUID(NSString *uid, NSError **error) {
    (void)error;
    for (MLAudioDevice *device in Devices) if ([device.uid isEqualToString:uid]) return device;
    return nil;
}
MLAudioDevice *MLMenuTestUniqueBuiltInInput(NSError **error) { (void)error; return BuiltIn; }
BOOL MLMenuTestSetDefaultInputUID(NSString *uid, NSError **error) {
    (void)uid; (void)error; HardwareWriteCount++; return NO;
}
void MLMenuTestAnalyticsRecordLockActivity(BOOL matching) { LastRecordedMatching = matching; }
void MLMenuTestAnalyticsRecordEvent(NSString *event) { (void)event; }
void MLMenuTestFeedbackRecordEvent(NSString *event) { (void)event; }
void MLMenuTestPostConfigurationChanged(void) { /* Do not notify the installed app. */ }

@interface MLMenuTestUpdateController : NSObject
@property(nonatomic) BOOL fakeCanCheck;
- (BOOL)canCheckForUpdates;
@end
@implementation MLMenuTestUpdateController
- (BOOL)canCheckForUpdates { return self.fakeCanCheck; }
@end

@interface MLMenuTestDelegate : MLAppDelegate
@property(nonatomic) SMAppServiceStatus fakeLoginStatus;
@property(nonatomic, copy) NSString *lastEnforcementReason;
@end
@implementation MLMenuTestDelegate
- (void)updateStatusIcon { /* No item is installed in the system menu bar. */ }
- (SMAppServiceStatus)launchAtLoginStatus { return self.fakeLoginStatus; }
- (void)scheduleEnforcement:(NSString *)reason { self.lastEnforcementReason = reason; }
@end

static void Check(BOOL condition, NSString *description) {
    CheckCount++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", description.UTF8String); exit(1); }
}
static NSMenuItem *ItemWithAction(NSMenu *menu, SEL action) {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action == action) return item;
        NSMenuItem *nested = item.submenu != nil ? ItemWithAction(item.submenu, action) : nil;
        if (nested != nil) return nested;
    }
    return nil;
}
static NSUInteger NonseparatorCount(NSMenu *menu) {
    NSUInteger count = 0;
    for (NSMenuItem *item in menu.itemArray) if (!item.isSeparatorItem) count++;
    return count;
}
static BOOL MenuHasTrailingEllipsis(NSMenu *menu) {
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.title hasSuffix:@"…"] || [item.title hasSuffix:@"..."]) return YES;
        if (item.submenu != nil && MenuHasTrailingEllipsis(item.submenu)) return YES;
    }
    return NO;
}
static NSButton *ButtonWithAction(NSView *view, SEL action) {
    if ([view isKindOfClass:NSButton.class] && [(NSButton *)view action] == action) return (NSButton *)view;
    for (NSView *child in view.subviews) {
        NSButton *button = ButtonWithAction(child, action);
        if (button != nil) return button;
    }
    return nil;
}
static BOOL ButtonsHaveTrailingEllipsis(NSView *view) {
    if ([view isKindOfClass:NSButton.class]) {
        NSString *title = [(NSButton *)view title];
        if ([title hasSuffix:@"…"] || [title hasSuffix:@"..."]) return YES;
    }
    for (NSView *child in view.subviews) if (ButtonsHaveTrailingEllipsis(child)) return YES;
    return NO;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *override = NSProcessInfo.processInfo.environment[@"MICLOCK_SUPPORT_DIR"];
        Check(override.isAbsolutePath && [override containsString:@"miclock-tests."], @"isolated configuration is required");
        Check(argc == 2, @"source directory is supplied for localization checks");
        [NSApplication sharedApplication];
        BuiltIn = [[MLAudioDevice alloc] init];
        BuiltIn.uid = @"test-built-in"; BuiltIn.name = @"Test computer microphone";
        BuiltIn.transportType = kAudioDeviceTransportTypeBuiltIn;
        Headset = [[MLAudioDevice alloc] init];
        Headset.uid = @"test-headset"; Headset.name = @"Test headset";
        Headset.transportType = kAudioDeviceTransportTypeBluetooth;
        Current = BuiltIn; Devices = @[BuiltIn, Headset];
        Check(MLSaveConfiguration(@{MLConfigTargetUIDKey:BuiltIn.uid, MLConfigTargetNameKey:BuiltIn.name,
            MLConfigEnabledKey:@YES}, NULL), @"fixture configuration created in temporary state");
        Check(MLSaveHealth(@{@"status":@"healthy", @"targetUID":BuiltIn.uid,
            @"processID":@(NSProcessInfo.processInfo.processIdentifier)}, NULL), @"active healthy fixture created");
        NSDictionary *before = MLLoadConfiguration();
        MLMenuTestDelegate *delegate = [[MLMenuTestDelegate alloc] init];
        delegate.statusMenu = [[NSMenu alloc] initWithTitle:@"MicLock"];
        delegate.statusMenu.autoenablesItems = NO;
        delegate.fakeLoginStatus = SMAppServiceStatusNotRegistered;
        MLMenuTestUpdateController *updater = [[MLMenuTestUpdateController alloc] init];
        delegate.updateController = (MLUpdateController *)(id)updater;
        [delegate rebuildMenu];
        NSMenu *menu = delegate.statusMenu;
        Check(NonseparatorCount(menu) == 10, @"healthy menu has only two status lines and eight everyday entries");
        NSMenu *targetMenu = ItemWithAction(menu, @selector(setLockTarget:)).menu;
        NSMenu *moreMenu = ItemWithAction(menu, @selector(toggleLaunchAtLogin:)).menu;
        Check(targetMenu.supermenu == menu && targetMenu.numberOfItems == 2,
              @"microphone configuration remains a direct first-level submenu");
        Check(moreMenu.supermenu == menu && !moreMenu.autoenablesItems,
              @"maintenance stays in More and preserves explicit action enablement");
        Check([moreMenu.title isEqualToString:MLL(@"More")], @"maintenance submenu uses a clear short title");
        NSArray<NSString *> *daily = @[@"toggleLock:", @"showStatusWindow:", @"showVoiceInputRecommendations:",
            @"showQuickStart:", @"reportIssue:", @"stopLockingAndQuit:"];
        for (NSString *name in daily) {
            NSMenuItem *item = ItemWithAction(menu, NSSelectorFromString(name));
            Check(item != nil && item.menu == menu && item.target == delegate && item.enabled,
                  [@"everyday action remains directly available: " stringByAppendingString:name]);
        }
        NSArray<NSString *> *maintenance = @[@"toggleLaunchAtLogin:", @"copySharingText:", @"showReleaseNotes:",
            @"checkForUpdates:", @"copyDiagnostics:", @"showAbout:", @"uninstall:"];
        for (NSString *name in maintenance) {
            NSMenuItem *item = ItemWithAction(menu, NSSelectorFromString(name));
            Check(item != nil && item.menu == moreMenu && item.target == delegate,
                  [@"maintenance action is retained in More: " stringByAppendingString:name]);
        }
        NSMenuItem *temporary = ItemWithAction(menu, @selector(switchNow:));
        Check(temporary.menu.supermenu == moreMenu && temporary.menu != targetMenu,
              @"temporary input switching is distinct from persistent configuration");
        NSMenuItem *temporaryParent = moreMenu.itemArray.firstObject;
        Check([temporaryParent.title isEqualToString:MLL(@"Switch Input Now (Pauses Lock)")],
              @"temporary switching explicitly warns that it pauses an active lock");
        Check(ItemWithAction(targetMenu, @selector(setLockTarget:)).state == NSControlStateValueOn &&
              targetMenu.itemArray.lastObject.state == NSControlStateValueOff,
              @"configuration device checkmark tracks saved target");
        Check(temporary.state == NSControlStateValueOn && temporary.menu.itemArray.lastObject.state == NSControlStateValueOff,
              @"temporary input checkmark tracks current microphone");
        for (NSMenu *deviceMenu in @[targetMenu, temporary.menu]) {
            Check([deviceMenu.itemArray.firstObject.representedObject isEqualToString:BuiltIn.uid] &&
                  [deviceMenu.itemArray.lastObject.representedObject isEqualToString:Headset.uid],
                  @"both device choices preserve stable identifiers");
        }
        Check([ItemWithAction(menu, @selector(showStatusWindow:)).keyEquivalent isEqualToString:@","] &&
              [ItemWithAction(menu, @selector(stopLockingAndQuit:)).keyEquivalent isEqualToString:@"q"],
              @"settings and quit keyboard shortcuts are retained");
        Check(!MenuHasTrailingEllipsis(menu) && !MenuHasTrailingEllipsis([delegate applicationMenu]),
              @"all production menu action titles omit trailing ellipses");
        Check(!ItemWithAction(menu, @selector(checkForUpdates:)).enabled,
              @"unavailable updater remains disabled after being moved into submenu");
        Check(ItemWithAction(menu, @selector(openLoginItemSettings:)) == nil,
              @"login approval link is absent when approval is not needed");
        updater.fakeCanCheck = YES; delegate.fakeLoginStatus = SMAppServiceStatusRequiresApproval;
        [delegate rebuildMenu];
        Check(ItemWithAction(menu, @selector(checkForUpdates:)).enabled,
              @"ready updater remains available in More");
        NSMenuItem *approval = ItemWithAction(menu, @selector(openLoginItemSettings:));
        Check(approval != nil && approval.menu.supermenu == menu && approval.enabled,
              @"required login approval remains reachable in More");
        delegate.fakeLoginStatus = SMAppServiceStatusEnabled; [delegate rebuildMenu];
        Check(ItemWithAction(menu, @selector(toggleLaunchAtLogin:)).state == NSControlStateValueOn &&
              ItemWithAction(menu, @selector(openLoginItemSettings:)) == nil,
              @"enabled login item is checked without an unnecessary approval action");
        [delegate showVoiceInputRecommendations:nil];
        Check(MLMenuTestWorkspace.sharedWorkspace.openCount == 1 &&
              [MLMenuTestWorkspace.sharedWorkspace.lastOpenedURL.absoluteString isEqualToString:
               @"https://ecnkfnba0c1r.feishuapp.com/app/app_17ftjhzb3vs/voice-input.html"],
              @"production recommendation action opens the exact personal product page with no browser launch in test");
        Check(HardwareWriteCount == 0 && [MLLoadConfiguration() isEqualToDictionary:before] && LastRecordedMatching,
              @"menu and recommendation navigation preserve microphone configuration and perform no hardware writes");
        NSMenuItem *headsetChoice = ItemWithAction(menu, @selector(setLockTarget:)).menu.itemArray.lastObject;
        [delegate setLockTarget:headsetChoice];
        Check([MLLoadConfiguration()[MLConfigTargetUIDKey] isEqualToString:Headset.uid] &&
              [MLLoadConfiguration()[MLConfigEnabledKey] boolValue] &&
              [delegate.lastEnforcementReason isEqualToString:@"target-changed"],
              @"configuring a microphone preserves an enabled lock and schedules the existing correction flow");
        Check(MLSetConfigurationEnabled(NO, NULL), @"pause fixture");
        NSMenuItem *builtInChoice = [[NSMenuItem alloc] initWithTitle:@"fixture" action:nil keyEquivalent:@""];
        builtInChoice.representedObject = BuiltIn.uid;
        [delegate setLockTarget:builtInChoice];
        Check([MLLoadConfiguration()[MLConfigTargetUIDKey] isEqualToString:BuiltIn.uid] &&
              ![MLLoadConfiguration()[MLConfigEnabledKey] boolValue] && HardwareWriteCount == 0,
              @"configuring a microphone while paused retains the pause instead of silently enabling locking");
        [delegate rebuildMenu];
        Check(ItemWithAction(menu, @selector(toggleLock:)).state == NSControlStateValueOff && !LastRecordedMatching,
              @"paused state is reflected without claiming successful locking");
        NSMenu *pausedMore = ItemWithAction(menu, @selector(toggleLaunchAtLogin:)).menu;
        Check([pausedMore.itemArray.firstObject.title isEqualToString:MLL(@"Switch Input Now")],
              @"paused switching no longer claims it will pause an active lock");
        Check(MLSetConfigurationEnabled(YES, NULL), @"restore active fixture");
        Current = Headset; Devices = @[Headset];
        Check(MLSaveHealth(@{@"status":@"waiting", @"targetUID":BuiltIn.uid,
            @"processID":@(NSProcessInfo.processInfo.processIdentifier), @"monitoring":@"fallback"}, NULL),
              @"missing target and fallback fixture created");
        [delegate rebuildMenu];
        Check(NonseparatorCount(menu) == 12 &&
              [menu.itemArray[2].title isEqualToString:[NSString stringWithFormat:MLL(@"Lock target: %@"), BuiltIn.name]] &&
              [menu.itemArray[3].title isEqualToString:MLL(@"Event monitoring unavailable; retrying every 5 seconds")],
              @"abnormal state keeps target and monitoring warnings instead of hiding actionable information");
        Devices = @[]; [delegate rebuildMenu];
        NSMenuItem *targetParent = menu.itemArray[5];
        Check(targetParent.submenu.numberOfItems == 1 && !targetParent.submenu.itemArray.firstObject.enabled,
              @"no-device state has a disabled descriptive placeholder");

        MLStatusWindowController *window = [[MLStatusWindowController alloc] init];
        NSButton *recommendations = ButtonWithAction(window.window.contentView, @selector(openVoiceInputRecommendations:));
        Check(recommendations != nil, @"settings includes a discoverable recommendation action");
        __block NSUInteger recommendationCallbacks = 0;
        window.onVoiceInputRecommendations = ^{ recommendationCallbacks++; };
        [recommendations performClick:nil];
        Check(recommendationCallbacks == 1, @"settings recommendation button invokes its callback");
        Check(!ButtonsHaveTrailingEllipsis(window.window.contentView), @"settings operation buttons omit ellipses");
        Check(!window.window.isReleasedWhenClosed && ![delegate applicationShouldTerminateAfterLastWindowClosed:NSApp],
              @"settings closure retains the companion lifecycle");
        NSString *source = [NSString stringWithUTF8String:argv[1]];
        NSArray<NSString *> *actionKeys = @[@"Status and Settings", @"Configure Microphone", @"Voice Input Recommendations",
            @"Quick Start", @"Report an Issue", @"More", @"Approve in System Settings", @"Version History",
            @"Check for Updates", @"Uninstall MicLock"];
        // The plist parser silently keeps one value for a duplicated strings
        // key. Inspect every quoted key in these line-based resources before
        // relying on the parsed dictionary to validate actual labels.
        NSRegularExpression *keyPattern = [NSRegularExpression regularExpressionWithPattern:
            @"(?m)^[ \\t]*\"((?:\\\\.|[^\"\\\\])*)\"[ \\t]*=" options:0 error:nil];
        for (NSString *language in @[@"en", @"zh-Hans"]) {
            NSString *path = [source stringByAppendingPathComponent:[NSString stringWithFormat:@"menu-app/%@.lproj/Localizable.strings", language]];
            NSDictionary *strings = [NSDictionary dictionaryWithContentsOfFile:path];
            Check(strings != nil, [@"localization parses: " stringByAppendingString:language]);
            NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            NSArray<NSTextCheckingResult *> *matches = [keyPattern matchesInString:contents options:0
                range:NSMakeRange(0, contents.length)];
            NSMutableSet<NSString *> *uniqueKeys = [NSMutableSet set];
            for (NSTextCheckingResult *match in matches) [uniqueKeys addObject:[contents substringWithRange:[match rangeAtIndex:1]]];
            Check(matches.count == uniqueKeys.count,
                  [@"localization keys are unique before dictionary parsing: " stringByAppendingString:language]);
            Check(matches.count > 0 && uniqueKeys.count == strings.count,
                  [@"all resource keys are accounted for by parsed dictionary: " stringByAppendingString:language]);
            for (NSString *key in actionKeys) {
                NSString *title = strings[key];
                Check(title.length > 0 && ![title hasSuffix:@"…"] && ![title hasSuffix:@"..."],
                      [NSString stringWithFormat:@"%@ action title is concise: %@", language, key]);
            }
            Check([strings[@"Quick Start Details"] containsString:strings[@"Voice Input Recommendations"]],
                  [@"quick start explains the separate input method and recommendation entry: " stringByAppendingString:language]);
        }
        printf("Production menu regression tests passed (%lu checks).\n", (unsigned long)CheckCount);
    }
    return 0;
}
