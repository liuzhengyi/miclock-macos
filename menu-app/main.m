#import <AppKit/AppKit.h>
#import <CoreAudio/CoreAudio.h>
#import <ServiceManagement/ServiceManagement.h>
#import <os/log.h>
#import <unistd.h>
#import "MLAudio.h"
#import "MLState.h"
#import "MLCorrectionPolicy.h"
#import "MLGuide.h"
#import "MLStatusWindow.h"
#import "MLUpdate.h"
#import "MLLifecycle.h"
#import "MLFeedback.h"
#import "MLAnalytics.h"
#import "MLStatusPlacement.h"

static NSString * const MLBundleIdentifier = @"io.github.liuzhengyi.miclock";
static NSString * const MLShowMenuNotification = @"io.github.liuzhengyi.miclock.show-menu";
static NSString * const MLShowMenuAcknowledgedNotification = @"io.github.liuzhengyi.miclock.show-menu-acknowledged";
static NSString * const MLShowStatusNotification = @"io.github.liuzhengyi.miclock.show-status";
static NSString * const MLShowStatusAcknowledgedNotification = @"io.github.liuzhengyi.miclock.show-status-acknowledged";
static os_log_t MLLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("io.github.liuzhengyi.miclock", "audio");
    });
    return log;
}

static NSString *MLL(NSString *key) {
    return [NSBundle.mainBundle localizedStringForKey:key value:key table:nil];
}

static NSString *MLHealthDisplayName(NSString *status) {
    if ([status isEqualToString:@"healthy"]) return MLL(@"Healthy");
    if ([status isEqualToString:@"corrected"]) return MLL(@"Corrected");
    if ([status isEqualToString:@"waiting"]) return MLL(@"Waiting for target device");
    if ([status isEqualToString:@"conflict"]) return MLL(@"Paused after repeated conflicts");
    if ([status isEqualToString:@"error"]) return MLL(@"Error");
    if ([status isEqualToString:@"needsTarget"]) return MLL(@"Choose a lock target");
    if ([status isEqualToString:@"notRunning"]) return MLL(@"MicLock is not running");
    return MLL(@"Paused");
}

static NSDictionary *MLDisplayHealth(NSDictionary *configuration) {
    NSMutableDictionary *health = [MLLoadHealth() mutableCopy];
    if (![configuration[MLConfigEnabledKey] boolValue]) {
        health[@"status"] = @"disabled";
        return health;
    }
    pid_t processID = [health[@"processID"] isKindOfClass:NSNumber.class]
        ? [health[@"processID"] intValue] : 0;
    NSRunningApplication *application = processID > 0
        ? [NSRunningApplication runningApplicationWithProcessIdentifier:processID] : nil;
    BOOL processExists = processID == NSProcessInfo.processInfo.processIdentifier ||
        [application.bundleIdentifier isEqualToString:MLBundleIdentifier];
    if (!processExists) health[@"status"] = @"notRunning";
    else if (![health[@"targetUID"] isEqualToString:configuration[MLConfigTargetUIDKey]]) {
        health[@"status"] = @"waiting";
    }
    return health;
}

static NSString *MLBadgeText(MLAudioDeviceKind kind) {
    switch (kind) {
        case MLAudioDeviceKindBuiltIn: return @"M";
        case MLAudioDeviceKindBluetooth: return @"B";
        case MLAudioDeviceKindExternal: return @"E";
        case MLAudioDeviceKindVirtual: return @"V";
        case MLAudioDeviceKindUnknown: return @"O";
    }
}

static NSColor *MLBadgeColor(MLAudioDeviceKind kind) {
    switch (kind) {
        case MLAudioDeviceKindBuiltIn: return NSColor.systemBlueColor;
        case MLAudioDeviceKindBluetooth: return NSColor.systemTealColor;
        case MLAudioDeviceKindExternal: return NSColor.systemPurpleColor;
        case MLAudioDeviceKindVirtual: return NSColor.systemOrangeColor;
        case MLAudioDeviceKindUnknown: return NSColor.systemGrayColor;
    }
}

#import "MLStatusBadgeView.h"

@interface MLAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) MLStatusBadgeView *badgeView;
@property(nonatomic, strong) NSMenu *statusMenu;
@property(nonatomic, strong) dispatch_queue_t audioQueue;
@property(nonatomic, copy) AudioObjectPropertyListenerBlock defaultInputListener;
@property(nonatomic, copy) AudioObjectPropertyListenerBlock deviceListListener;
@property(nonatomic, strong) MLCorrectionPolicy *correctionPolicy;
@property(nonatomic, strong) dispatch_source_t correctionRetryTimer;
@property(nonatomic, strong) dispatch_source_t listenerRecoveryTimer;
@property(nonatomic) BOOL defaultInputListenerInstalled;
@property(nonatomic) BOOL deviceListListenerInstalled;
@property(nonatomic, copy) NSString *listenerWarning;
@property(nonatomic, copy) NSString *lastConfigurationSignature;
@property(nonatomic, copy) NSString *lastIconSignature;
@property(nonatomic, copy) NSString *lastMenuRequestID;
@property(nonatomic, copy) NSString *lastStatusRequestID;
@property(nonatomic, strong) MLStatusWindowController *statusWindowController;
@property(nonatomic, strong) MLFeedbackWindowController *feedbackWindowController;
@property(nonatomic, strong) MLUpdateController *updateController;
@property(nonatomic, strong) MLLifecycleController *lifecycleController;
@property(nonatomic) BOOL audioPublicationPending;
@property(atomic) BOOL uninstalling;
@end

@implementation MLAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSApp.mainMenu = [self applicationMenu];
    NSApp.windowsMenu = NSApp.mainMenu.itemArray.lastObject.submenu;
    self.audioQueue = dispatch_queue_create("io.github.liuzhengyi.miclock.audio", DISPATCH_QUEUE_SERIAL);
    self.correctionPolicy = [[MLCorrectionPolicy alloc] init];
    [self configureInitialTargetIfPossible];
    [self createStatusItem];
    [self installObservers];
    MLFeedbackRecordEvent(@"launch");
    MLAnalyticsRecordEvent(@"app_started");
    self.updateController = [[MLUpdateController alloc] init];
    [self scheduleEnforcement:@"launch"];
    // Direct launch always gives a visible configuration window. A login item
    // launch stays in the menu bar, without interrupting the user's work.
    NSAppleEventDescriptor *event = NSAppleEventManager.sharedAppleEventManager.currentAppleEvent;
    BOOL loginLaunch = [event paramDescriptorForKeyword:keyAEPropData].enumCodeValue == keyAELaunchedAsLogInItem;
    if (!loginLaunch) dispatch_async(dispatch_get_main_queue(), ^{ [self showStatusWindow:nil]; });
}

// AppKit routes common text and window keyboard equivalents through the
// application's main menu, including for accessory apps with menu-bar UI.
// Nil targets preserve the first-responder chain for feedback text editing.
- (NSMenu *)applicationMenu {
    NSMenu *root = [[NSMenu alloc] initWithTitle:@"MicLock"];
    NSMenuItem *app = [[NSMenuItem alloc] initWithTitle:@"MicLock" action:nil keyEquivalent:@""];
    app.submenu = [[NSMenu alloc] initWithTitle:@"MicLock"];
    [app.submenu addItem:[self actionItem:MLL(@"About MicLock") action:@selector(showAbout:)]];
    NSMenuItem *settings = [self actionItem:MLL(@"Status and Settings") action:@selector(showStatusWindow:)];
    settings.keyEquivalent = @",";
    [app.submenu addItem:settings];
    [app.submenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [self actionItem:MLL(@"Stop Locking and Quit") action:@selector(stopLockingAndQuit:)];
    quit.keyEquivalent = @"q";
    [app.submenu addItem:quit];
    [root addItem:app];

    NSMenuItem *edit = [[NSMenuItem alloc] initWithTitle:MLL(@"Edit") action:nil keyEquivalent:@""];
    edit.submenu = [[NSMenu alloc] initWithTitle:MLL(@"Edit")];
    NSArray<NSArray<NSString *> *> *editing = @[
        @[@"Undo", @"undo:", @"z"], @[@"Redo", @"redo:", @"z"],
        @[@"Cut", @"cut:", @"x"], @[@"Copy", @"copy:", @"c"],
        @[@"Paste", @"paste:", @"v"], @[@"Select All", @"selectAll:", @"a"]
    ];
    for (NSUInteger index = 0; index < editing.count; index++) {
        if (index == 2) [edit.submenu addItem:NSMenuItem.separatorItem];
        NSArray<NSString *> *entry = editing[index];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:MLL(entry[0])
            action:NSSelectorFromString(entry[1]) keyEquivalent:entry[2]];
        item.keyEquivalentModifierMask = NSEventModifierFlagCommand |
            (index == 1 ? NSEventModifierFlagShift : 0);
        [edit.submenu addItem:item];
    }
    [root addItem:edit];
    NSMenuItem *windows = [[NSMenuItem alloc] initWithTitle:MLL(@"Window") action:nil keyEquivalent:@""];
    windows.submenu = [[NSMenu alloc] initWithTitle:MLL(@"Window")];
    [windows.submenu addItem:[[NSMenuItem alloc] initWithTitle:MLL(@"Close Window")
        action:@selector(performClose:) keyEquivalent:@"w"]];
    [windows.submenu addItem:[[NSMenuItem alloc] initWithTitle:MLL(@"Minimize")
        action:@selector(performMiniaturize:) keyEquivalent:@"m"]];
    [root addItem:windows];
    return root;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    dispatch_sync(self.audioQueue, ^{
        [self cancelCorrectionRetry];
        if (self.listenerRecoveryTimer != nil) {
            dispatch_source_cancel(self.listenerRecoveryTimer);
            self.listenerRecoveryTimer = nil;
        }
    });
    if (self.defaultInputListenerInstalled) {
        AudioObjectPropertyAddress address = {
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject, &address,
                                               dispatch_get_main_queue(), self.defaultInputListener);
    }
    if (self.deviceListListenerInstalled) {
        AudioObjectPropertyAddress address = {
            kAudioHardwarePropertyDevices,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject, &address,
                                               dispatch_get_main_queue(), self.deviceListListener);
    }
    [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    if (self.statusItem == nil) [self createStatusItem];
    self.statusItem.visible = YES;
    [self rebuildMenu];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return NO; // Closing settings never removes the menu bar companion.
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (self.statusItem == nil) [self createStatusItem];
    [self showStatusWindow:nil];
    return YES;
}

- (void)configureInitialTargetIfPossible {
    NSError *error = nil;
    if (!MLInitializeConfiguration(&error)) {
        os_log_error(MLLog(), "Could not initialize configuration: %{private}@", error.localizedDescription);
    }
}

- (void)createStatusItem {
    // Activation can arrive before applicationDidFinishLaunching. Keep that
    // original button rather than replacing it with an unpainted status item.
    if (self.statusItem != nil) {
        self.statusItem.visible = YES;
        [self updateStatusIcon];
        [self rebuildMenu];
        return;
    }
    self.lastIconSignature = nil;
    self.statusMenu = [[NSMenu alloc] initWithTitle:@"MicLock"];
    self.statusMenu.delegate = self;
    self.statusMenu.autoenablesItems = NO;
    NSScreen *screen = NSScreen.mainScreen;
    if (screen == nil) screen = NSScreen.screens.firstObject;
    CGFloat rightAreaWidth = screen != nil && screen.safeAreaInsets.top > 0
        ? NSWidth(screen.auxiliaryTopRightArea) : 0;
    CGFloat availableWidth = rightAreaWidth > 0 ? rightAreaWidth
        : (screen != nil ? NSWidth(screen.frame) : 0);
    MLStatusPlacementPrepareDefaults(NSUserDefaults.standardUserDefaults,
                                    MLBundleIdentifier, availableWidth);
    // Give the item its stable identity before asking Control Center to host
    // visible content (particularly important for the macOS 26 scene host).
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:0];
    self.statusItem.autosaveName = MLBundleIdentifier;
    self.statusItem.menu = self.statusMenu;
    self.statusItem.behavior = 0; // Do not offer drag-to-remove while MicLock runs.
    self.statusItem.visible = YES;
    self.statusItem.button.imagePosition = NSImageOnly;
    self.statusItem.button.title = @"";

    self.badgeView = [[MLStatusBadgeView alloc] initWithFrame:NSZeroRect];
    self.badgeView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statusItem.button addSubview:self.badgeView];
    [NSLayoutConstraint activateConstraints:@[
        [self.badgeView.widthAnchor constraintEqualToConstant:9.5],
        [self.badgeView.heightAnchor constraintEqualToConstant:9.5],
        [self.badgeView.trailingAnchor constraintEqualToAnchor:self.statusItem.button.trailingAnchor constant:-1.0],
        [self.badgeView.bottomAnchor constraintEqualToAnchor:self.statusItem.button.bottomAnchor constant:1.0],
    ]];
    [self updateStatusIcon];
    self.statusItem.length = NSSquareStatusItemLength;
    [self rebuildMenu];
}

- (void)installObservers {
    MLAppDelegate * __weak weakSelf = self;
    self.defaultInputListener = ^(UInt32 count, const AudioObjectPropertyAddress *addresses) {
        (void)count;
        (void)addresses;
        [weakSelf scheduleEnforcement:@"default-input-changed"];
    };
    self.deviceListListener = ^(UInt32 count, const AudioObjectPropertyAddress *addresses) {
        (void)count;
        (void)addresses;
        [weakSelf scheduleEnforcement:@"device-list-changed"];
    };
    [self registerAudioListeners];
    if (!self.defaultInputListenerInstalled || !self.deviceListListenerInstalled) {
        self.listenerRecoveryTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.audioQueue);
        dispatch_source_set_timer(self.listenerRecoveryTimer,
            dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, NSEC_PER_SEC);
        dispatch_source_set_event_handler(self.listenerRecoveryTimer, ^{
            MLAppDelegate *strongSelf = weakSelf;
            if (strongSelf == nil) return;
            [strongSelf registerAudioListeners];
            [strongSelf enforceDefaultInputForReason:@"listener-recovery"];
            [strongSelf publishAudioState];
            if (strongSelf.defaultInputListenerInstalled && strongSelf.deviceListListenerInstalled) {
                dispatch_source_cancel(strongSelf.listenerRecoveryTimer);
                strongSelf.listenerRecoveryTimer = nil;
            }
        });
        dispatch_resume(self.listenerRecoveryTimer);
    }

    [NSDistributedNotificationCenter.defaultCenter addObserver:self
                                                       selector:@selector(configurationChanged:)
                                                           name:MLConfigChangedNotification object:nil];
    [NSDistributedNotificationCenter.defaultCenter addObserver:self
                                                       selector:@selector(terminateRequested:)
                                                           name:MLTerminateNotification object:nil];
    [NSDistributedNotificationCenter.defaultCenter addObserver:self
                                                       selector:@selector(showMenuRequested:)
                                                           name:MLShowMenuNotification object:nil];
    [NSDistributedNotificationCenter.defaultCenter addObserver:self
                                                       selector:@selector(showStatusRequested:)
                                                           name:MLShowStatusNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self
                                                        selector:@selector(workspaceDidWake:)
                                                            name:NSWorkspaceDidWakeNotification object:nil];
}

- (void)registerAudioListeners {
    NSMutableArray<NSString *> *warnings = [NSMutableArray array];
    if (!self.defaultInputListenerInstalled) {
        AudioObjectPropertyAddress address = {
            kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        OSStatus result = AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &address,
            dispatch_get_main_queue(), self.defaultInputListener);
        self.defaultInputListenerInstalled = result == noErr;
        if (result != noErr) [warnings addObject:MLAudioError(result, @"Default input listener").localizedDescription];
    }
    if (!self.deviceListListenerInstalled) {
        AudioObjectPropertyAddress address = {
            kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        OSStatus result = AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &address,
            dispatch_get_main_queue(), self.deviceListListener);
        self.deviceListListenerInstalled = result == noErr;
        if (result != noErr) [warnings addObject:MLAudioError(result, @"Device list listener").localizedDescription];
    }
    self.listenerWarning = [warnings componentsJoinedByString:@"; "];
    if (warnings.count > 0) MLFeedbackRecordEvent(@"listener-failed");
}

- (void)configurationChanged:(NSNotification *)notification {
    [self scheduleEnforcement:@"configuration-changed"];
}

- (void)terminateRequested:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
}

- (void)showMenuRequested:(NSNotification *)notification {
    NSString *requestID = [notification.object isKindOfClass:NSString.class] ? notification.object : nil;
    NSNumber *processID = [notification.userInfo[@"processID"] isKindOfClass:NSNumber.class]
        ? notification.userInfo[@"processID"] : nil;
    if (requestID.length == 0 || processID.intValue != NSProcessInfo.processInfo.processIdentifier) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSDistributedNotificationCenter.defaultCenter postNotificationName:MLShowMenuAcknowledgedNotification
            object:requestID userInfo:nil deliverImmediately:YES];
        if ([self.lastMenuRequestID isEqualToString:requestID]) return;
        self.lastMenuRequestID = requestID;
        if (self.statusItem == nil) [self createStatusItem];
        [self rebuildMenu];
        [NSApp activateIgnoringOtherApps:YES];
        [self.statusItem.button performClick:nil];
    });
}

- (void)showStatusRequested:(NSNotification *)notification {
    NSString *requestID = [notification.object isKindOfClass:NSString.class] ? notification.object : nil;
    NSNumber *processID = [notification.userInfo[@"processID"] isKindOfClass:NSNumber.class]
        ? notification.userInfo[@"processID"] : nil;
    if (requestID.length == 0 || processID.intValue != NSProcessInfo.processInfo.processIdentifier) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self.lastStatusRequestID isEqualToString:requestID]) {
            self.lastStatusRequestID = requestID;
            [self showStatusWindow:nil];
        }
        if (self.statusWindowController.window.visible) {
            [NSDistributedNotificationCenter.defaultCenter postNotificationName:MLShowStatusAcknowledgedNotification
                object:requestID userInfo:nil deliverImmediately:YES];
        }
    });
}

- (void)workspaceDidWake:(NSNotification *)notification {
    [self scheduleEnforcement:@"wake"];
}

- (void)menuWillOpen:(NSMenu *)menu {
    [self rebuildMenu];
}

- (void)scheduleEnforcement:(NSString *)reason {
    if (self.uninstalling) return;
    dispatch_async(self.audioQueue, ^{
        if (self.uninstalling) return;
        [self enforceDefaultInputForReason:reason];
        [self publishAudioState];
    });
}

- (void)publishAudioState {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.audioPublicationPending) return;
        self.audioPublicationPending = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.audioPublicationPending = NO;
            [self rebuildMenu];
        });
    });
}

- (void)cancelCorrectionRetry {
    if (self.correctionRetryTimer != nil) {
        dispatch_source_cancel(self.correctionRetryTimer);
        self.correctionRetryTimer = nil;
    }
}

- (void)scheduleCorrectionRetryAfter:(NSTimeInterval)delay {
    [self cancelCorrectionRetry];
    self.correctionRetryTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.audioQueue);
    MLAppDelegate * __weak weakSelf = self;
    dispatch_source_set_event_handler(self.correctionRetryTimer, ^{
        MLAppDelegate *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        [strongSelf cancelCorrectionRetry];
        [strongSelf enforceDefaultInputForReason:@"scheduled-retry"];
        [strongSelf publishAudioState];
    });
    dispatch_source_set_timer(self.correctionRetryTimer,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)((delay > 0.1 ? delay : 0.1) * NSEC_PER_SEC)),
        DISPATCH_TIME_FOREVER, 100 * NSEC_PER_MSEC);
    dispatch_resume(self.correctionRetryTimer);
}

- (void)saveHealthStatus:(NSString *)status
                 message:(NSString *)message
                 current:(MLAudioDevice *)current
                  target:(MLAudioDevice *)target
                 enabled:(BOOL)enabled {
    NSString *previousStatus = MLLoadHealth()[@"status"];
    if ([status isEqualToString:@"conflict"] && ![previousStatus isEqualToString:@"conflict"]) {
        MLFeedbackRecordEvent(@"correction-backoff");
    } else if ([previousStatus isEqualToString:@"conflict"] &&
        ([status isEqualToString:@"healthy"] || [status isEqualToString:@"corrected"])) {
        MLFeedbackRecordEvent(@"correction-resumed");
    }
    NSMutableDictionary *health = [@{
        @"status": status,
        @"message": message != nil ? message : @"",
        @"enabled": @(enabled),
        @"processID": @(NSProcessInfo.processInfo.processIdentifier),
        @"version": NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] != nil
            ? NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] : @"unknown",
        @"monitoring": self.listenerWarning.length > 0 ? @"fallback" : @"events",
        @"monitoringMessage": self.listenerWarning != nil ? self.listenerWarning : @"",
    } mutableCopy];
    if (current != nil) {
        health[@"currentUID"] = current.uid;
        health[@"currentName"] = current.name;
    }
    if (target != nil) {
        health[@"targetUID"] = target.uid;
        health[@"targetName"] = target.name;
    }
    MLSaveHealth(health, NULL);
}

- (void)enforceDefaultInputForReason:(NSString *)reason {
    NSError *error = nil;
    if (!MLWithLockedConfiguration(^BOOL(NSDictionary *configuration, NSError **innerError) {
        (void)innerError;
        [self enforceConfiguration:configuration forReason:reason];
        return YES;
    }, &error)) {
        [self saveHealthStatus:@"error" message:error.localizedDescription current:nil target:nil enabled:NO];
    }
}

- (void)enforceConfiguration:(NSDictionary *)configuration forReason:(NSString *)reason {
    BOOL enabled = [configuration[MLConfigEnabledKey] boolValue];
    NSString *configurationSignature = [NSString stringWithFormat:@"%@|%@",
        @(enabled), configuration[MLConfigTargetUIDKey] != nil ? configuration[MLConfigTargetUIDKey] : @""];
    if (![configurationSignature isEqualToString:self.lastConfigurationSignature]) {
        [self.correctionPolicy reset];
        [self cancelCorrectionRetry];
        self.lastConfigurationSignature = configurationSignature;
    }
    NSError *currentError = nil;
    MLAudioDevice *current = MLAudioCurrentInput(&currentError);
    if (!enabled) {
        [self cancelCorrectionRetry];
        [self saveHealthStatus:@"disabled" message:@"" current:current target:nil enabled:NO];
        return;
    }

    NSString *targetUID = configuration[MLConfigTargetUIDKey];
    if (targetUID.length == 0) {
        [self saveHealthStatus:@"needsTarget" message:@"No target configured"
                       current:current target:nil enabled:YES];
        return;
    }
    NSError *targetError = nil;
    MLAudioDevice *target = MLAudioDeviceForUID(targetUID, &targetError);
    if (target == nil) {
        if (targetError != nil) [self scheduleCorrectionRetryAfter:5.0];
        [self saveHealthStatus:@"waiting" message:(targetError.localizedDescription != nil
            ? targetError.localizedDescription : @"Target unavailable")
                       current:current target:nil enabled:YES];
        return;
    }
    if (current == nil) {
        [self scheduleCorrectionRetryAfter:5.0];
        [self saveHealthStatus:@"error" message:(currentError.localizedDescription != nil
            ? currentError.localizedDescription : @"Current input unavailable")
                       current:nil target:target enabled:YES];
        return;
    }
    if ([current.uid isEqualToString:target.uid]) {
        [self cancelCorrectionRetry];
        [self saveHealthStatus:@"healthy" message:@"" current:current target:target enabled:YES];
        return;
    }

    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    NSTimeInterval retryAfter = 0;
    if (![self.correctionPolicy mayCorrectAtTime:now retryAfter:&retryAfter]) {
        [self scheduleCorrectionRetryAfter:retryAfter];
        [self saveHealthStatus:@"conflict" message:@"Repeated external audio routing changes"
                       current:current target:target enabled:YES];
        return;
    }
    NSError *setError = nil;
    if (!MLAudioSetDefaultInputUID(target.uid, &setError)) {
        [self.correctionPolicy recordCorrectionAtTime:now];
        [self scheduleCorrectionRetryAfter:5.0];
        [self saveHealthStatus:@"error" message:(setError.localizedDescription != nil
            ? setError.localizedDescription : @"Switch failed")
                       current:current target:target enabled:YES];
        os_log_error(MLLog(), "Could not select target input: %{private}@", setError.localizedDescription);
        return;
    }
    [self.correctionPolicy recordCorrectionAtTime:now];
    MLAudioDevice *after = MLAudioCurrentInput(NULL);
    if (after != nil && [after.uid isEqualToString:target.uid]) {
        [self saveHealthStatus:@"corrected" message:reason current:after target:target enabled:YES];
        os_log_info(MLLog(), "Restored the configured default input after %{public}@", reason);
    } else {
        [self scheduleCorrectionRetryAfter:1.0];
        [self saveHealthStatus:@"error" message:@"CoreAudio did not retain the selected input"
                       current:after target:target enabled:YES];
    }
}

- (NSImage *)statusTemplateImageLocked:(BOOL)locked accessibilityLabel:(NSString *)label {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(20.0, 18.0)];
    [image lockFocus];
    NSGraphicsContext.currentContext.shouldAntialias = YES;
    NSColor *ink = [NSColor colorWithWhite:0.0 alpha:(locked ? 1.0 : 0.62)];
    [ink setStroke];
    NSRect capsuleRect = NSMakeRect(5.0, 7.2, 7.2, 9.5);
    NSBezierPath *capsule = [NSBezierPath bezierPathWithRoundedRect:capsuleRect xRadius:3.6 yRadius:3.6];
    capsule.lineWidth = 1.45;
    if (locked) { [ink setFill]; [capsule fill]; } else { [capsule stroke]; }
    NSBezierPath *yoke = [NSBezierPath bezierPath];
    yoke.lineWidth = 1.45;
    yoke.lineCapStyle = NSLineCapStyleRound;
    [yoke moveToPoint:NSMakePoint(3.3, 10.5)];
    [yoke curveToPoint:NSMakePoint(8.6, 5.0)
         controlPoint1:NSMakePoint(3.3, 7.1) controlPoint2:NSMakePoint(5.6, 5.0)];
    [yoke curveToPoint:NSMakePoint(13.9, 10.5)
         controlPoint1:NSMakePoint(11.6, 5.0) controlPoint2:NSMakePoint(13.9, 7.1)];
    [yoke stroke];
    NSBezierPath *stand = [NSBezierPath bezierPath];
    stand.lineWidth = 1.45;
    stand.lineCapStyle = NSLineCapStyleRound;
    [stand moveToPoint:NSMakePoint(8.6, 5.0)];
    [stand lineToPoint:NSMakePoint(8.6, 2.5)];
    [stand moveToPoint:NSMakePoint(6.1, 2.3)];
    [stand lineToPoint:NSMakePoint(11.1, 2.3)];
    [stand stroke];
    [image unlockFocus];
    image.template = YES;
    image.accessibilityDescription = label;
    return image;
}

- (void)updateStatusIcon {
    NSDictionary *configuration = MLLoadConfiguration();
    NSDictionary *health = MLDisplayHealth(configuration);
    BOOL enabled = [configuration[MLConfigEnabledKey] boolValue];
    MLAudioDevice *current = MLAudioCurrentInput(NULL);
    NSString *healthStatus = health[@"status"] != nil ? health[@"status"]
        : (enabled ? @"waiting" : @"disabled");
    BOOL healthy = enabled && ([healthStatus isEqualToString:@"healthy"] ||
                               [healthStatus isEqualToString:@"corrected"]);
    NSString *currentName = current.name != nil ? current.name : MLL(@"Unavailable");
    NSString *targetName = configuration[MLConfigTargetNameKey] != nil
        ? configuration[MLConfigTargetNameKey] : MLL(@"Not configured");
    NSString *description = [NSString stringWithFormat:
        MLL(@"Current input: %@; target: %@; status: %@"),
        currentName, targetName, MLHealthDisplayName(healthStatus)];
    NSString *signature = [NSString stringWithFormat:@"%@|%@|%@",
        current.uid != nil ? current.uid : @"", healthStatus, @(enabled)];
    if (self.statusItem.button.image == nil ||
        ![signature isEqualToString:self.lastIconSignature]) {
        self.statusItem.button.image = [self statusTemplateImageLocked:healthy accessibilityLabel:description];
        self.lastIconSignature = signature;
    }
    self.statusItem.button.toolTip = description;
    [self.statusItem.button setAccessibilityLabel:@"MicLock"];
    [self.statusItem.button setAccessibilityValue:description];
    if (enabled && !healthy && ![healthStatus isEqualToString:@"corrected"]) {
        self.badgeView.badgeColor = NSColor.systemRedColor;
        self.badgeView.badgeText = @"!";
    } else {
        self.badgeView.badgeColor = current != nil ? MLBadgeColor(current.kind) : NSColor.systemRedColor;
        self.badgeView.badgeText = current != nil ? MLBadgeText(current.kind) : @"!";
    }
    [self.badgeView setNeedsDisplay:YES];
}

- (NSMenuItem *)disabledItem:(NSString *)title {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    item.enabled = NO;
    return item;
}

- (NSMenuItem *)actionItem:(NSString *)title action:(SEL)action {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    item.enabled = YES;
    return item;
}

- (NSMenu *)deviceMenuWithAction:(SEL)action selectedUID:(NSString *)selectedUID
                         devices:(NSArray<MLAudioDevice *> *)devices {
    NSMenu *menu = [[NSMenu alloc] init];
    if (devices.count == 0) {
        [menu addItem:[self disabledItem:MLL(@"No input devices available")]];
        return menu;
    }
    for (MLAudioDevice *device in devices) {
        NSString *title = [NSString stringWithFormat:@"%@ — %@", device.name, MLL(device.transportLabel)];
        NSMenuItem *item = [self actionItem:title action:action];
        item.representedObject = device.uid;
        item.state = [device.uid isEqualToString:selectedUID] ? NSControlStateValueOn : NSControlStateValueOff;
        item.toolTip = title;
        [menu addItem:item];
    }
    return menu;
}

// Keep everyday operations one click away; maintenance and temporary routing
// stay in More. Reading this status must never register or alter the login item.
- (SMAppServiceStatus)launchAtLoginStatus {
    return SMAppService.mainAppService.status;
}

- (void)rebuildMenu {
    [self.statusMenu removeAllItems];
    NSDictionary *configuration = MLLoadConfiguration();
    NSDictionary *health = MLDisplayHealth(configuration);
    BOOL enabled = [configuration[MLConfigEnabledKey] boolValue];
    MLAudioDevice *current = MLAudioCurrentInput(NULL);
    NSArray<MLAudioDevice *> *devices = MLAudioInputDevices(NULL);
    NSString *targetUID = configuration[MLConfigTargetUIDKey] != nil
        ? configuration[MLConfigTargetUIDKey] : @"";
    NSString *targetName = configuration[MLConfigTargetNameKey] != nil
        ? configuration[MLConfigTargetNameKey] : MLL(@"Not configured");
    NSString *healthStatus = health[@"status"] != nil ? health[@"status"]
        : (enabled ? @"waiting" : @"disabled");

    [self.statusMenu addItem:[self disabledItem:[NSString stringWithFormat:MLL(@"Current input: %@"),
                                                 current.name != nil ? current.name : MLL(@"Unavailable")]]];
    [self.statusMenu addItem:[self disabledItem:[NSString stringWithFormat:MLL(@"Status: %@"),
                                                 MLHealthDisplayName(healthStatus)]]];
    // Healthy current input already identifies the chosen microphone. Show the
    // saved target separately only when it helps explain a disconnected device
    // or other active lock problem; full details stay in Status and Settings.
    BOOL matching = enabled && current != nil && [current.uid isEqualToString:targetUID] &&
        ([healthStatus isEqualToString:@"healthy"] || [healthStatus isEqualToString:@"corrected"]);
    if (enabled && !matching && targetUID.length > 0) {
        [self.statusMenu addItem:[self disabledItem:[NSString stringWithFormat:MLL(@"Lock target: %@"), targetName]]];
    }
    if ([health[@"monitoring"] isEqualToString:@"fallback"]) {
        [self.statusMenu addItem:[self disabledItem:MLL(@"Event monitoring unavailable; retrying every 5 seconds")]];
    }
    [self.statusMenu addItem:NSMenuItem.separatorItem];

    NSMenuItem *target = [self actionItem:MLL(@"Configure Microphone") action:nil];
    target.submenu = [self deviceMenuWithAction:@selector(setLockTarget:) selectedUID:targetUID devices:devices];
    [self.statusMenu addItem:target];
    NSMenuItem *toggle = [self actionItem:(enabled ? MLL(@"Automatic lock: On") : MLL(@"Automatic lock: Off"))
                                    action:@selector(toggleLock:)];
    toggle.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    toggle.image = [NSImage imageWithSystemSymbolName:(enabled ? @"mic.fill" : @"mic")
                             accessibilityDescription:toggle.title];
    [self.statusMenu addItem:toggle];
    NSMenuItem *settings = [self actionItem:MLL(@"Status and Settings") action:@selector(showStatusWindow:)];
    settings.keyEquivalent = @",";
    [self.statusMenu addItem:settings];
    [self.statusMenu addItem:NSMenuItem.separatorItem];

    [self.statusMenu addItem:[self actionItem:MLL(@"Voice Input Recommendations")
                                           action:@selector(showVoiceInputRecommendations:)]];
    [self.statusMenu addItem:[self actionItem:MLL(@"Quick Start") action:@selector(showQuickStart:)]];
    [self.statusMenu addItem:[self actionItem:MLL(@"Report an Issue") action:@selector(reportIssue:)]];

    NSMenuItem *more = [self actionItem:MLL(@"More") action:nil];
    more.submenu = [[NSMenu alloc] initWithTitle:MLL(@"More")];
    // Explicit enablement (especially the update controller) must survive
    // AppKit submenu validation just as it does for the top-level menu.
    more.submenu.autoenablesItems = NO;
    NSMenuItem *switchNow = [self actionItem:(enabled
        ? MLL(@"Switch Input Now (Pauses Lock)") : MLL(@"Switch Input Now")) action:nil];
    switchNow.submenu = [self deviceMenuWithAction:@selector(switchNow:)
                                        selectedUID:current.uid != nil ? current.uid : @"" devices:devices];
    [more.submenu addItem:switchNow];
    SMAppServiceStatus loginStatus = [self launchAtLoginStatus];
    NSString *loginTitle = loginStatus == SMAppServiceStatusEnabled
        ? MLL(@"Launch at Login: On") : MLL(@"Launch at Login: Off");
    NSMenuItem *login = [self actionItem:loginTitle action:@selector(toggleLaunchAtLogin:)];
    login.state = loginStatus == SMAppServiceStatusEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [more.submenu addItem:login];
    if (loginStatus == SMAppServiceStatusRequiresApproval) {
        [more.submenu addItem:[self actionItem:MLL(@"Approve in System Settings")
                                              action:@selector(openLoginItemSettings:)]];
    }
    [more.submenu addItem:NSMenuItem.separatorItem];
    [more.submenu addItem:[self actionItem:MLL(@"Copy Sharing Text") action:@selector(copySharingText:)]];
    [more.submenu addItem:[self actionItem:MLL(@"Version History") action:@selector(showReleaseNotes:)]];
    NSMenuItem *update = [self actionItem:MLL(@"Check for Updates") action:@selector(checkForUpdates:)];
    update.enabled = self.updateController.canCheckForUpdates;
    [more.submenu addItem:update];
    [more.submenu addItem:NSMenuItem.separatorItem];
    [more.submenu addItem:[self actionItem:MLL(@"Copy Redacted Diagnostics") action:@selector(copyDiagnostics:)]];
    [more.submenu addItem:[self actionItem:MLL(@"About MicLock") action:@selector(showAbout:)]];
    [more.submenu addItem:[self actionItem:MLL(@"Uninstall MicLock") action:@selector(uninstall:)]];
    [self.statusMenu addItem:more];
    [self.statusMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [self actionItem:MLL(@"Stop Locking and Quit") action:@selector(stopLockingAndQuit:)];
    quit.keyEquivalent = @"q";
    [self.statusMenu addItem:quit];
    [self updateStatusIcon];
    [self.statusWindowController updateWithCurrentInput:current configuration:configuration health:health
        healthDisplayName:MLHealthDisplayName(healthStatus) devices:devices];
    MLAnalyticsRecordLockActivity(matching);
}

- (void)showErrorTitle:(NSString *)title detail:(NSString *)detail {
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = title;
    alert.informativeText = detail;
    [alert addButtonWithTitle:MLL(@"OK")];
    [alert addButtonWithTitle:MLL(@"Copy Diagnostics")];
    if ([alert runModal] == NSAlertSecondButtonReturn) [self copyDiagnostics:nil];
}

- (BOOL)saveEnabled:(BOOL)enabled error:(NSError **)error {
    if (!MLSetConfigurationEnabled(enabled, error)) return NO;
    MLPostConfigurationChanged();
    return YES;
}

- (void)toggleLock:(NSMenuItem *)sender {
    if (self.uninstalling) return;
    BOOL enabled = [MLLoadConfiguration()[MLConfigEnabledKey] boolValue];
    NSError *error = nil;
    if (![self saveEnabled:!enabled error:&error]) {
        [self showErrorTitle:MLL(@"Could Not Change MicLock") detail:error.localizedDescription];
        return;
    }
    [self scheduleEnforcement:@"toggle"];
    MLFeedbackRecordEvent(@"toggle-lock");
}

- (void)switchNow:(NSMenuItem *)sender {
    if (self.uninstalling) return;
    NSString *uid = [sender.representedObject isKindOfClass:NSString.class] ? sender.representedObject : @"";
    NSError *error = nil;
    if ([MLLoadConfiguration()[MLConfigEnabledKey] boolValue] && ![self saveEnabled:NO error:&error]) {
        [self showErrorTitle:MLL(@"Could Not Switch Microphone") detail:error.localizedDescription];
        return;
    }
    if (!MLAudioSetDefaultInputUID(uid, &error)) {
        [self showErrorTitle:MLL(@"Could Not Switch Microphone") detail:error.localizedDescription];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        MLAudioDevice *after = MLAudioCurrentInput(NULL);
        if (after == nil || ![after.uid isEqualToString:uid]) {
            [self showErrorTitle:MLL(@"Could Not Switch Microphone")
                           detail:MLL(@"macOS or another app immediately changed the input again.")];
        }
        [self updateStatusIcon];
    });
    MLFeedbackRecordEvent(@"switch-input");
}

- (void)setLockTarget:(NSMenuItem *)sender {
    if (self.uninstalling) return;
    NSString *uid = [sender.representedObject isKindOfClass:NSString.class] ? sender.representedObject : @"";
    MLAudioDevice *device = MLAudioDeviceForUID(uid, NULL);
    if (device == nil) {
        [self showErrorTitle:MLL(@"Could Not Set Lock Target") detail:MLL(@"The selected device is no longer available.")];
        return;
    }
    NSDictionary *changes = @{
        MLConfigTargetUIDKey: device.uid,
        MLConfigTargetNameKey: device.name,
    };
    NSError *error = nil;
    if (!MLUpdateConfiguration(changes, &error)) {
        [self showErrorTitle:MLL(@"Could Not Set Lock Target") detail:error.localizedDescription];
        return;
    }
    MLPostConfigurationChanged();
    [self scheduleEnforcement:@"target-changed"];
    MLFeedbackRecordEvent(@"select-target");
}

- (void)toggleLaunchAtLogin:(NSMenuItem *)sender {
    SMAppService *service = SMAppService.mainAppService;
    NSError *error = nil;
    BOOL success = service.status == SMAppServiceStatusEnabled
        ? [service unregisterAndReturnError:&error]
        : [service registerAndReturnError:&error];
    if (!success) {
        [self showErrorTitle:MLL(@"Could Not Change Login Setting") detail:error.localizedDescription];
    }
    [self rebuildMenu];
}

- (void)openLoginItemSettings:(NSMenuItem *)sender {
    [SMAppService openSystemSettingsLoginItems];
}

- (NSString *)redactedDiagnostics {
    NSDictionary *configuration = MLLoadConfiguration();
    NSDictionary *health = MLDisplayHealth(configuration);
    MLAudioDevice *current = MLAudioCurrentInput(NULL);
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"MicLock %@\n",
        NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] != nil
            ? NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] : @"unknown"];
    [text appendFormat:@"macOS: %@\n", NSProcessInfo.processInfo.operatingSystemVersionString];
    [text appendFormat:@"enabled: %@\n", [configuration[MLConfigEnabledKey] boolValue] ? @"yes" : @"no"];
    [text appendFormat:@"health: %@\n", health[@"status"] != nil ? health[@"status"] : @"unknown"];
    [text appendFormat:@"current: %@ (%@)\n",
        current.transportLabel != nil ? current.transportLabel : @"unknown",
        MLRedactedIdentifier(current.uid != nil ? current.uid : @"")];
    [text appendFormat:@"target: %@\n", MLRedactedIdentifier(
        configuration[MLConfigTargetUIDKey] != nil ? configuration[MLConfigTargetUIDKey] : @"")];
    [text appendFormat:@"visible inputs: %lu\n", (unsigned long)MLAudioInputDevices(NULL).count];
    return text;
}

- (void)copyDiagnostics:(NSMenuItem *)sender {
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:[self redactedDiagnostics] forType:NSPasteboardTypeString];
}

- (void)reportIssue:(NSMenuItem *)sender {
    (void)sender;
    if (self.feedbackWindowController == nil) self.feedbackWindowController = [[MLFeedbackWindowController alloc] init];
    [self.feedbackWindowController showWindow:nil];
    [self.feedbackWindowController.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showQuickStart:(NSMenuItem *)sender {
    (void)sender;
    MLShowUsageGuide(YES);
}

- (void)showVoiceInputRecommendations:(NSMenuItem *)sender {
    (void)sender;
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:
        @"https://ecnkfnba0c1r.feishuapp.com/app/app_17ftjhzb3vs/voice-input.html"]];
}

- (void)showStatusWindow:(NSMenuItem *)sender {
    (void)sender;
    if (self.statusWindowController == nil) {
        self.statusWindowController = [[MLStatusWindowController alloc] init];
        MLAppDelegate * __weak weakSelf = self;
        self.statusWindowController.onToggleAutomaticLock = ^{
            [weakSelf toggleLock:nil];
            [weakSelf rebuildMenu];
        };
        self.statusWindowController.onSelectTarget = ^(NSString *uid) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
            item.representedObject = uid;
            [weakSelf setLockTarget:item];
            [weakSelf rebuildMenu];
        };
        self.statusWindowController.onQuickStart = ^{ [weakSelf showQuickStart:nil]; };
        self.statusWindowController.onVoiceInputRecommendations = ^{ [weakSelf showVoiceInputRecommendations:nil]; };
        self.statusWindowController.onCopyDiagnostics = ^{ [weakSelf copyDiagnostics:nil]; };
        self.statusWindowController.onReportIssue = ^{ [weakSelf reportIssue:nil]; };
        self.statusWindowController.onCheckForUpdates = ^{ [weakSelf checkForUpdates:nil]; };
        self.statusWindowController.onVersionHistory = ^{ [weakSelf showReleaseNotes:nil]; };
        self.statusWindowController.onUninstall = ^{ [weakSelf uninstall:nil]; };
        self.statusWindowController.onAnalyticsConsentChanged = ^(BOOL enabled) {
            MLAnalyticsSetEnabled(enabled);
            [weakSelf rebuildMenu];
        };
    }
    [self rebuildMenu];
    [self.statusWindowController showWindow:nil];
    [self.statusWindowController.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)copySharingText:(NSMenuItem *)sender {
    (void)sender;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:MLL(@"Sharing Text") forType:NSPasteboardTypeString];
}

- (void)openReleases:(NSMenuItem *)sender {
    (void)sender;
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://ecnkfnba0c1r.feishuapp.com/app/app_17ftjhzb3vs#download"]];
}

- (void)showAbout:(NSMenuItem *)sender {
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanel:nil];
}

- (void)checkForUpdates:(id)sender {
    MLAnalyticsRecordEvent(@"update_checked");
    [self.updateController checkForUpdates:sender];
}
- (void)showReleaseNotes:(id)sender { [self.updateController showReleaseNotes:sender]; }
- (void)uninstall:(id)sender {
    if (self.lifecycleController == nil) {
        self.lifecycleController = [[MLLifecycleController alloc] init];
        MLAppDelegate * __weak weakSelf = self;
        self.lifecycleController.onPrepareForUninstall = ^BOOL(NSError **error) {
            MLAppDelegate *strongSelf = weakSelf;
            if (strongSelf == nil || ![strongSelf saveEnabled:NO error:error]) return NO;
            MLAnalyticsRecordEvent(@"uninstall_requested");
            strongSelf.uninstalling = YES;
            dispatch_sync(strongSelf.audioQueue, ^{
                [strongSelf cancelCorrectionRetry];
                if (strongSelf.listenerRecoveryTimer != nil) {
                    dispatch_source_cancel(strongSelf.listenerRecoveryTimer);
                    strongSelf.listenerRecoveryTimer = nil;
                }
            });
            return YES;
        };
        self.lifecycleController.onUninstallFailed = ^{
            weakSelf.uninstalling = NO;
            [weakSelf scheduleEnforcement:@"uninstall-cancelled"];
        };
    }
    [self.lifecycleController uninstall:sender];
}

- (void)stopLockingAndQuit:(NSMenuItem *)sender {
    NSError *error = nil;
    if (![self saveEnabled:NO error:&error]) {
        [self showErrorTitle:MLL(@"Could Not Disable MicLock") detail:error.localizedDescription];
        return;
    }
    [NSApp terminate:nil];
}

@end


static void MLPrint(NSString *text) {
    fprintf(stdout, "%s\n", text.UTF8String != NULL ? text.UTF8String : "");
}

static void MLPrintError(NSString *text) {
    fprintf(stderr, "%s\n", text.UTF8String != NULL ? text.UTF8String : "");
}

static MLAudioDevice *MLResolveDevice(NSString *token, NSError **error) {
    NSArray<MLAudioDevice *> *devices = MLAudioInputDevices(error);
    for (MLAudioDevice *device in devices) {
        if ([device.uid isEqualToString:token]) return device;
    }
    NSArray<MLAudioDevice *> *matches = [devices filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(MLAudioDevice *device, NSDictionary *bindings) {
            (void)bindings;
            return [device.name isEqualToString:token];
        }]];
    if (matches.count == 1) return matches.firstObject;
    if (error != NULL) {
        NSString *message = matches.count > 1
            ? MLL(@"More than one device has that name; use the UID shown by mic-list.")
            : [NSString stringWithFormat:MLL(@"Input device not found: %@"), token];
        *error = [NSError errorWithDomain:MLBundleIdentifier code:2
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return nil;
}

static BOOL MLCLISaveEnabled(BOOL enabled, NSError **error) {
    if (!MLSetConfigurationEnabled(enabled, error)) return NO;
    MLPostConfigurationChanged();
    return YES;
}

static BOOL MLLaunchGUI(NSError **error) {
    for (NSRunningApplication *application in
         [NSRunningApplication runningApplicationsWithBundleIdentifier:MLBundleIdentifier]) {
        if (application.processIdentifier != NSProcessInfo.processInfo.processIdentifier && !application.terminated) {
            return YES;
        }
    }
    NSURL *bundleURL = NSBundle.mainBundle.bundleURL;
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *launchError = nil;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:bundleURL configuration:configuration
                                    completionHandler:^(NSRunningApplication *application, NSError *value) {
        (void)application;
        launchError = value;
        dispatch_semaphore_signal(semaphore);
    }];
    // NSWorkspace may deliver its completion on the main queue. The CLI runs
    // on the main thread, so a blocking semaphore wait can hide completion.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
    BOOL completed = NO;
    while ([deadline timeIntervalSinceNow] > 0) {
        if (dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW) == 0) {
            completed = YES;
            break;
        }
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                              beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    if (!completed && dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW) == 0) completed = YES;
    if (!completed) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:MLBundleIdentifier code:4
                userInfo:@{NSLocalizedDescriptionKey: MLL(@"MicLock launch timed out. Open the app and try again.")}];
        }
        return NO;
    }
    if (launchError != nil && error != NULL) *error = launchError;
    return launchError == nil;
}

static BOOL MLCLIRequestUI(NSString *requestNotification, NSString *acknowledgedNotification,
                          NSString *timeoutMessage, NSError **error) {
    if (!MLLaunchGUI(error)) return NO;
    NSString *requestID = NSUUID.UUID.UUIDString;
    __block BOOL acknowledged = NO;
    id observer = [NSDistributedNotificationCenter.defaultCenter
        addObserverForName:acknowledgedNotification object:requestID queue:nil
        usingBlock:^(NSNotification *notification) { (void)notification; acknowledged = YES; }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
    id savedProcessID = MLLoadHealth()[@"processID"];
    pid_t preferredProcessID = [savedProcessID isKindOfClass:NSNumber.class] ? [savedProcessID intValue] : 0;
    while (!acknowledged && [deadline timeIntervalSinceNow] > 0) {
        NSRunningApplication *target = nil;
        for (NSRunningApplication *application in
             [NSRunningApplication runningApplicationsWithBundleIdentifier:MLBundleIdentifier]) {
            if (application.processIdentifier == NSProcessInfo.processInfo.processIdentifier || application.terminated) continue;
            if (target == nil || application.processIdentifier == preferredProcessID) target = application;
        }
        if (target != nil && target.finishedLaunching) {
            [NSDistributedNotificationCenter.defaultCenter postNotificationName:requestNotification
                object:requestID userInfo:@{@"processID":@(target.processIdentifier)} deliverImmediately:YES];
        }
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                              beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    [NSDistributedNotificationCenter.defaultCenter removeObserver:observer];
    if (!acknowledged && error != NULL) {
        *error = [NSError errorWithDomain:MLBundleIdentifier code:5
            userInfo:@{NSLocalizedDescriptionKey: MLL(timeoutMessage)}];
    }
    return acknowledged;
}

static void MLPrintUsage(void) {
    MLPrint(MLL(@"Usage: miclock <command>"));
    MLPrint(@"");
    MLPrint(MLL(@"  status               Show lock health and the current input"));
    MLPrint(MLL(@"  on                   Enable automatic locking and start MicLock"));
    MLPrint(MLL(@"  off                  Pause automatic locking"));
    MLPrint(MLL(@"  quit                 Disable locking and quit MicLock"));
    MLPrint(MLL(@"  fix                  Restore the configured input once"));
    MLPrint(MLL(@"  list                 List input devices and stable UIDs"));
    MLPrint(MLL(@"  use NAME_OR_UID       Set the persistent lock target"));
    MLPrint(MLL(@"  switch NAME_OR_UID    Switch once without changing the target"));
    MLPrint(MLL(@"  pick                 Choose a lock target interactively"));
    MLPrint(MLL(@"  diagnostics          Print redacted diagnostics"));
    MLPrint(MLL(@"  show-menu            Open the menu bar menu, starting MicLock if needed"));
    MLPrint(MLL(@"  show-status          Open Status and Settings, starting MicLock if needed"));
}

static int MLCLI(NSArray<NSString *> *arguments) {
    NSString *invocation = @"miclock";
    NSMutableArray<NSString *> *values = [arguments mutableCopy];
    if (values.count > 0 && ([values.firstObject isEqualToString:@"miclock"] ||
        [values.firstObject hasPrefix:@"mic-"])) {
        invocation = values.firstObject;
        [values removeObjectAtIndex:0];
    }
    NSDictionary *aliases = @{
        @"mic-on": @"on", @"mic-start": @"on", @"mic-off": @"off",
        @"mic-quit": @"quit", @"mic-status": @"status", @"mic-list": @"list",
        @"mic-fix": @"fix", @"mic-pick": @"pick", @"mic-set": @"use",
    };
    NSString *command = aliases[invocation] != nil ? aliases[invocation]
        : (values.firstObject != nil ? values.firstObject : @"status");
    if (aliases[invocation] == nil && values.count > 0) [values removeObjectAtIndex:0];

    if ([command isEqualToString:@"help"] || [command isEqualToString:@"--help"] ||
        [command isEqualToString:@"-h"]) {
        MLPrintUsage();
        return 0;
    }
    if ([command isEqualToString:@"show-menu"]) {
        NSError *error = nil;
        if (!MLCLIRequestUI(MLShowMenuNotification, MLShowMenuAcknowledgedNotification,
            @"MicLock menu request timed out. Open the app and try again.", &error)) {
            MLPrintError(error.localizedDescription);
            return 1;
        }
        MLPrint(MLL(@"MicLock accepted the menu-opening request."));
        return 0;
    }
    if ([command isEqualToString:@"show-status"]) {
        NSError *error = nil;
        if (!MLCLIRequestUI(MLShowStatusNotification, MLShowStatusAcknowledgedNotification,
            @"MicLock status window request timed out. Open the app and try again.", &error)) {
            MLPrintError(error.localizedDescription);
            return 1;
        }
        MLPrint(MLL(@"MicLock opened Status and Settings."));
        return 0;
    }
    if ([command isEqualToString:@"list"]) {
        NSError *error = nil;
        NSArray<MLAudioDevice *> *devices = MLAudioInputDevices(&error);
        if (error != nil) { MLPrintError(error.localizedDescription); return 1; }
        NSUInteger index = 1;
        for (MLAudioDevice *device in devices) {
            MLPrint([NSString stringWithFormat:@"%lu. %@ [%@] — %@",
                (unsigned long)index++, device.name, device.uid, device.transportLabel]);
        }
        return devices.count > 0 ? 0 : 1;
    }
    if ([command isEqualToString:@"status"]) {
        NSDictionary *configuration = MLLoadConfiguration();
        NSDictionary *health = MLDisplayHealth(configuration);
        MLAudioDevice *current = MLAudioCurrentInput(NULL);
        MLPrint([NSString stringWithFormat:MLL(@"Automatic lock: %@"),
            [configuration[MLConfigEnabledKey] boolValue] ? MLL(@"On") : MLL(@"Off")]);
        MLPrint([NSString stringWithFormat:MLL(@"Health: %@"),
            MLHealthDisplayName(health[@"status"] != nil ? health[@"status"] : @"disabled")]);
        MLPrint([NSString stringWithFormat:MLL(@"Lock target: %@"),
            configuration[MLConfigTargetNameKey] != nil
                ? configuration[MLConfigTargetNameKey] : MLL(@"Not configured")]);
        MLPrint([NSString stringWithFormat:MLL(@"Current input: %@"),
            current.name != nil ? current.name : MLL(@"Unavailable")]);
        return 0;
    }
    if ([command isEqualToString:@"on"] || [command isEqualToString:@"off"] ||
        [command isEqualToString:@"quit"]) {
        NSError *error = nil;
        BOOL enabled = [command isEqualToString:@"on"];
        if (!MLCLISaveEnabled(enabled, &error)) {
            MLPrintError(error.localizedDescription); return 1;
        }
        if (enabled && !MLLaunchGUI(&error)) {
            MLPrintError(error.localizedDescription); return 1;
        }
        if ([command isEqualToString:@"quit"]) MLPostTerminate();
        MLPrint(enabled ? MLL(@"Automatic microphone locking is enabled.")
                        : MLL(@"Automatic microphone locking is paused."));
        return 0;
    }
    if ([command isEqualToString:@"login-status"]) {
        return SMAppService.mainAppService.status == SMAppServiceStatusEnabled ? 0 : 1;
    }
    if ([command isEqualToString:@"login-on"] || [command isEqualToString:@"login-off"]) {
        SMAppService *service = SMAppService.mainAppService;
        NSError *error = nil;
        BOOL shouldEnable = [command isEqualToString:@"login-on"];
        if ((shouldEnable && service.status == SMAppServiceStatusEnabled) ||
            (!shouldEnable && service.status == SMAppServiceStatusNotRegistered)) {
            return 0;
        }
        BOOL success = shouldEnable ? [service registerAndReturnError:&error]
                                    : [service unregisterAndReturnError:&error];
        if (!success) {
            MLPrintError(error.localizedDescription);
            return 1;
        }
        return 0;
    }
    if ([command isEqualToString:@"init-built-in"]) {
        MLAudioDevice *builtIn = MLAudioUniqueBuiltInInput(NULL);
        if (builtIn == nil) {
            MLPrintError(MLL(@"No unique built-in microphone was found; choose a target manually."));
            return 1;
        }
        NSDictionary *changes = @{
            MLConfigTargetUIDKey: builtIn.uid,
            MLConfigTargetNameKey: builtIn.name,
        };
        NSError *error = nil;
        if (!MLUpdateConfiguration(changes, &error)) { MLPrintError(error.localizedDescription); return 1; }
        MLPostConfigurationChanged();
        MLPrint([NSString stringWithFormat:MLL(@"Lock target: %@"), builtIn.name]);
        return 0;
    }
    if ([command isEqualToString:@"init-configuration"]) {
        NSError *error = nil;
        if (!MLInitializeConfiguration(&error)) {
            MLPrintError(error.localizedDescription);
            return 1;
        }
        MLPostConfigurationChanged();
        return 0;
    }
    if ([command isEqualToString:@"fix"]) {
        NSString *uid = MLLoadConfiguration()[MLConfigTargetUIDKey];
        if (uid.length == 0) { MLPrintError(MLL(@"No lock target is configured.")); return 1; }
        NSError *error = nil;
        if (!MLAudioSetDefaultInputUID(uid, &error)) { MLPrintError(error.localizedDescription); return 1; }
        MLPrint(MLL(@"The configured input was restored."));
        return 0;
    }
    if ([command isEqualToString:@"use"] || [command isEqualToString:@"switch"]) {
        NSString *token = values.firstObject != nil ? values.firstObject : @"";
        if (token.length == 0) { MLPrintUsage(); return 2; }
        NSError *error = nil;
        MLAudioDevice *device = MLResolveDevice(token, &error);
        if (device == nil) { MLPrintError(error.localizedDescription); return 1; }
        if ([command isEqualToString:@"use"]) {
            NSDictionary *changes = @{
                MLConfigTargetUIDKey: device.uid,
                MLConfigTargetNameKey: device.name,
            };
            if (!MLUpdateConfiguration(changes, &error)) { MLPrintError(error.localizedDescription); return 1; }
            MLPostConfigurationChanged();
        } else if ([MLLoadConfiguration()[MLConfigEnabledKey] boolValue]) {
            if (!MLCLISaveEnabled(NO, &error)) { MLPrintError(error.localizedDescription); return 1; }
        }
        if (!MLAudioSetDefaultInputUID(device.uid, &error)) { MLPrintError(error.localizedDescription); return 1; }
        if ([command isEqualToString:@"switch"]) {
            usleep(300000);
            MLAudioDevice *after = MLAudioCurrentInput(NULL);
            if (after == nil || ![after.uid isEqualToString:device.uid]) {
                MLPrintError(MLL(@"macOS or another app immediately changed the input again."));
                return 1;
            }
        }
        MLPrint([NSString stringWithFormat:MLL(@"Current input: %@"), device.name]);
        return 0;
    }
    if ([command isEqualToString:@"pick"]) {
        NSArray<MLAudioDevice *> *devices = MLAudioInputDevices(NULL);
        if (devices.count == 0) { MLPrintError(MLL(@"No input devices available")); return 1; }
        NSUInteger index = 1;
        for (MLAudioDevice *device in devices) {
            MLPrint([NSString stringWithFormat:@"%lu) %@ — %@", (unsigned long)index++,
                device.name, device.transportLabel]);
        }
        fprintf(stdout, "%s", [MLL(@"Choose a lock target by number: ") UTF8String]);
        fflush(stdout);
        char input[32] = {0};
        if (fgets(input, sizeof(input), stdin) == NULL) return 1;
        NSInteger choice = [[NSString stringWithUTF8String:input] integerValue];
        if (choice < 1 || choice > (NSInteger)devices.count) {
            MLPrintError(MLL(@"Selection is out of range.")); return 1;
        }
        MLAudioDevice *device = devices[(NSUInteger)choice - 1];
        NSDictionary *changes = @{
            MLConfigTargetUIDKey: device.uid,
            MLConfigTargetNameKey: device.name,
        };
        NSError *error = nil;
        if (!MLUpdateConfiguration(changes, &error) ||
            !MLAudioSetDefaultInputUID(device.uid, &error)) {
            MLPrintError(error.localizedDescription); return 1;
        }
        MLPostConfigurationChanged();
        MLPrint([NSString stringWithFormat:MLL(@"Lock target: %@"), device.name]);
        return 0;
    }
    if ([command isEqualToString:@"diagnostics"] || [command isEqualToString:@"logs"]) {
        NSDictionary *configuration = MLLoadConfiguration();
        NSDictionary *health = MLDisplayHealth(configuration);
        MLAudioDevice *current = MLAudioCurrentInput(NULL);
        MLPrint([NSString stringWithFormat:@"MicLock %@",
            NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] != nil
                ? NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] : @"unknown"]);
        MLPrint([NSString stringWithFormat:@"macOS: %@", NSProcessInfo.processInfo.operatingSystemVersionString]);
        MLPrint([NSString stringWithFormat:@"enabled: %@",
            [configuration[MLConfigEnabledKey] boolValue] ? @"yes" : @"no"]);
        MLPrint([NSString stringWithFormat:@"health: %@",
            health[@"status"] != nil ? health[@"status"] : @"unknown"]);
        MLPrint([NSString stringWithFormat:@"current: %@ (%@)",
            current.transportLabel != nil ? current.transportLabel : @"unknown",
            MLRedactedIdentifier(current.uid != nil ? current.uid : @"")]);
        MLPrint([NSString stringWithFormat:@"target: %@",
            MLRedactedIdentifier(configuration[MLConfigTargetUIDKey] != nil
                ? configuration[MLConfigTargetUIDKey] : @"")]);
        MLPrint(@"Unified log: log show --last 10m --predicate 'subsystem == \"io.github.liuzhengyi.miclock\"'");
        return 0;
    }
    MLPrintUsage();
    return 2;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSMutableArray<NSString *> *arguments = [NSMutableArray array];
        for (int index = 1; index < argc; index++) {
            NSString *argument = [NSString stringWithUTF8String:argv[index]];
            [arguments addObject:argument != nil ? argument : @""];
        }
        if (arguments.count > 0 && [arguments.firstObject isEqualToString:@"--cli"]) {
            [arguments removeObjectAtIndex:0];
            return MLCLI(arguments);
        }
        if (arguments.count == 1 && [arguments.firstObject isEqualToString:@"--guide"]) {
            return MLRunStandaloneGuide();
        }
        NSApplication *application = NSApplication.sharedApplication;
        MLAppDelegate *delegate = [[MLAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
