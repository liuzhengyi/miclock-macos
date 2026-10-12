#import <Foundation/Foundation.h>

// Compile the actual coordinator against fake hardware. No device write,
// application launch, login-item call, visible status item, or real user state is exercised.
#define MLAudioCurrentInput MLTestCurrentInput
#define MLAudioInputDevices MLTestInputDevices
#define MLAudioDeviceForUID MLTestDeviceForUID
#define MLAudioSetDefaultInputUID MLTestSetDefaultInputUID
#define MLAudioUniqueBuiltInInput MLTestUniqueBuiltInInput
#define AudioObjectAddPropertyListenerBlock MLTestAddPropertyListenerBlock
#define main MLTestProductionEntrypoint
#include "../menu-app/main.m"
#undef main
#undef MLAudioCurrentInput
#undef MLAudioInputDevices
#undef MLAudioDeviceForUID
#undef MLAudioSetDefaultInputUID
#undef MLAudioUniqueBuiltInInput
#undef AudioObjectAddPropertyListenerBlock

static MLAudioDevice *FakeTarget;
static MLAudioDevice *FakeOther;
static MLAudioDevice *FakeCurrent;
static NSUInteger WriteCount;
static NSUInteger DefaultListenerAttempts;
static NSUInteger DeviceListenerAttempts;
static BOOL FailDefaultListener = YES;

MLAudioDevice *MLTestCurrentInput(NSError **error) { (void)error; return FakeCurrent; }
NSArray<MLAudioDevice *> *MLTestInputDevices(NSError **error) {
    (void)error;
    return @[FakeTarget, FakeOther];
}
MLAudioDevice *MLTestDeviceForUID(NSString *uid, NSError **error) {
    (void)error;
    return [uid isEqualToString:FakeTarget.uid] ? FakeTarget : nil;
}
MLAudioDevice *MLTestUniqueBuiltInInput(NSError **error) { (void)error; return FakeTarget; }
BOOL MLTestSetDefaultInputUID(NSString *uid, NSError **error) {
    (void)error;
    if (![uid isEqualToString:FakeTarget.uid]) return NO;
    WriteCount++;
    FakeCurrent = FakeTarget;
    return YES;
}
OSStatus MLTestAddPropertyListenerBlock(AudioObjectID object,
    const AudioObjectPropertyAddress *address, dispatch_queue_t queue,
    AudioObjectPropertyListenerBlock listener) {
    (void)object; (void)queue; (void)listener;
    if (address->mSelector == kAudioHardwarePropertyDefaultInputDevice) {
        DefaultListenerAttempts++;
        return FailDefaultListener ? kAudioHardwareIllegalOperationError : noErr;
    }
    DeviceListenerAttempts++;
    return noErr;
}

static void Assert(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}

static NSMenuItem *FindMenuAction(NSMenu *menu, SEL action) {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action == action) return item;
        NSMenuItem *nested = item.submenu != nil ? FindMenuAction(item.submenu, action) : nil;
        if (nested != nil) return nested;
    }
    return nil;
}

@interface MLTestDelegate : MLAppDelegate
@property(nonatomic, copy) void (^didPublish)(void);
@end
@implementation MLTestDelegate
- (void)publishAudioState { if (self.didPublish != nil) self.didPublish(); }
- (void)updateStatusIcon { /* Menu model tests do not attach a real status item. */ }
@end

int main(void) {
    @autoreleasepool {
        NSString *override = NSProcessInfo.processInfo.environment[@"MICLOCK_SUPPORT_DIR"];
        Assert(override.isAbsolutePath && [override containsString:@"miclock-tests."],
               @"requires isolated temporary configuration");
        FakeTarget = [[MLAudioDevice alloc] init];
        FakeTarget.uid = @"fake-built-in"; FakeTarget.name = @"Fake built-in";
        FakeTarget.transportType = kAudioDeviceTransportTypeBuiltIn;
        FakeOther = [[MLAudioDevice alloc] init];
        FakeOther.uid = @"fake-headset"; FakeOther.name = @"Fake headset";
        FakeOther.transportType = kAudioDeviceTransportTypeBluetooth;
        FakeCurrent = FakeOther;
        Assert(MLSaveConfiguration(@{MLConfigTargetUIDKey:FakeTarget.uid,
            MLConfigTargetNameKey:FakeTarget.name, MLConfigEnabledKey:@YES}, NULL), @"isolated fixture created");
        Assert(MLSaveHealth(@{@"status":@"healthy", @"processID":@0}, NULL), @"stale health fixture created");
        Assert([MLDisplayHealth(MLLoadConfiguration())[@"status"] isEqualToString:@"notRunning"],
               @"old healthy snapshot cannot imply an active lock process");
        Assert(MLSetConfigurationEnabled(NO, NULL), @"pause stale health fixture");
        Assert([MLDisplayHealth(MLLoadConfiguration())[@"status"] isEqualToString:@"disabled"],
               @"paused configuration overrides a stale healthy snapshot");
        Assert(MLSetConfigurationEnabled(YES, NULL), @"restore enabled fake device fixture");
        MLTestDelegate *delegate = [[MLTestDelegate alloc] init];
        delegate.audioQueue = dispatch_queue_create("miclock.test.hardware", DISPATCH_QUEUE_SERIAL);
        delegate.correctionPolicy = [[MLCorrectionPolicy alloc] init];
        delegate.defaultInputListener = ^(UInt32 count, const AudioObjectPropertyAddress *addresses) {
            (void)count; (void)addresses;
        };
        delegate.deviceListListener = delegate.defaultInputListener;
        [delegate registerAudioListeners];
        Assert(!delegate.defaultInputListenerInstalled && delegate.deviceListListenerInstalled &&
               delegate.listenerWarning.length > 0, @"listener failure is explicit");
        FailDefaultListener = NO;
        [delegate registerAudioListeners];
        Assert(delegate.defaultInputListenerInstalled && delegate.listenerWarning.length == 0 &&
               DefaultListenerAttempts == 2 && DeviceListenerAttempts == 1,
               @"retry only failed listeners without duplicate successful registration");

        dispatch_semaphore_t recovered = dispatch_semaphore_create(0);
        delegate.didPublish = ^{ dispatch_semaphore_signal(recovered); };
        dispatch_sync(delegate.audioQueue, ^{
            for (NSUInteger index = 0; index < 6; index++) {
                FakeCurrent = FakeOther;
                [delegate enforceDefaultInputForReason:@"fake-external-change"];
            }
            Assert(WriteCount == 5, @"sixth external change causes backoff without hardware write");
            Assert([MLLoadHealth()[@"status"] isEqualToString:@"conflict"] &&
                   delegate.correctionRetryTimer != nil, @"conflict installs a real retry timer");
        });
        printf("Waiting for the actual 30-second retry timer against fake hardware...\n");
        fflush(stdout);
        Assert(dispatch_semaphore_wait(recovered,
            dispatch_time(DISPATCH_TIME_NOW, 35 * NSEC_PER_SEC)) == 0,
            @"cooldown expiry automatically retries without another audio event");
        dispatch_sync(delegate.audioQueue, ^{
            Assert(WriteCount == 6 && FakeCurrent == FakeTarget &&
                   [MLLoadHealth()[@"status"] isEqualToString:@"corrected"],
                   @"scheduled retry restores the target after external conflict stops");
            Assert(delegate.correctionRetryTimer == nil, @"successful retry cancels timer");
        });
        // Exercise the production menu graph against fake devices. No status
        // item is installed and no selection action is invoked on hardware.
        NSMenu *applicationMenu = [delegate applicationMenu];
        NSMenu *editing = applicationMenu.itemArray[1].submenu;
        for (NSArray *entry in @[@[@"paste:",@"v"],@[@"copy:",@"c"],@[@"cut:",@"x"],@[@"selectAll:",@"a"]]) {
            NSMenuItem *match = nil;
            for (NSMenuItem *item in editing.itemArray) if (item.action == NSSelectorFromString(entry[0])) match = item;
            Assert(match != nil && match.target == nil && [match.keyEquivalent isEqualToString:entry[1]],
                @"native text shortcuts route through first responder");
        }
        NSMenuItem *close = applicationMenu.itemArray[2].submenu.itemArray.firstObject;
        Assert(close.action == @selector(performClose:) && close.target == nil && [close.keyEquivalent isEqualToString:@"w"],
            @"standard window close shortcut is available");
        delegate.statusMenu = [[NSMenu alloc] initWithTitle:@"test"];
        [delegate rebuildMenu];
        for (NSString *selectorName in @[@"showStatusWindow:", @"toggleLock:", @"toggleLaunchAtLogin:",
            @"showQuickStart:", @"showVoiceInputRecommendations:", @"showReleaseNotes:", @"checkForUpdates:", @"reportIssue:",
            @"uninstall:", @"stopLockingAndQuit:"]) {
            SEL selector = NSSelectorFromString(selectorName);
            NSMenuItem *match = FindMenuAction(delegate.statusMenu, selector);
            Assert(match != nil && match.target == delegate && [delegate respondsToSelector:selector],
                   [NSString stringWithFormat:@"production menu keeps the %@ action", selectorName]);
        }
        NSMenuItem *targetDevice = FindMenuAction(delegate.statusMenu, @selector(setLockTarget:));
        NSMenuItem *temporaryDevice = FindMenuAction(delegate.statusMenu, @selector(switchNow:));
        for (NSMenuItem *device in @[targetDevice, temporaryDevice]) {
            Assert(device.menu.numberOfItems == 2, @"both fake microphones remain configurable");
            for (NSMenuItem *choice in device.menu.itemArray) {
                Assert([choice.representedObject isEqualToString:FakeTarget.uid] ||
                       [choice.representedObject isEqualToString:FakeOther.uid], @"menu action retains stable device UID");
            }
        }
        Assert(targetDevice.menu != temporaryDevice.menu,
               @"one-time switch and persistent target remain separate shortcuts");
        NSMenu *persistentMenu = delegate.statusMenu;
        [delegate rebuildMenu];
        Assert(delegate.statusMenu == persistentMenu, @"refresh keeps the same menu object");
        delegate.uninstalling = YES;
        NSUInteger beforeUninstall = WriteCount;
        [delegate scheduleEnforcement:@"uninstall-test"];
        dispatch_sync(delegate.audioQueue, ^{});
        Assert(WriteCount == beforeUninstall, @"uninstall preparation blocks new audio enforcement");
        delegate.uninstalling = NO;
        printf("Fake hardware enforcement tests passed.\n");
    }
    return 0;
}
