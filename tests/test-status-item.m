#import <AppKit/AppKit.h>
#import "MLAudio.h"
#import "MLStatusPlacement.h"

// Exercise the real coordinator and image renderer without installing an item
// in the user's menu bar. Only the NSStatusBar factory and hardware reads are
// substituted. No window is shown, device is changed, observer is installed,
// login item is registered, or network request is made. On-screen visibility,
// physical clicks, and closing the real settings window require live acceptance.
@interface MLPlacementMemoryDefaults : NSUserDefaults
@property(nonatomic, strong) NSMutableDictionary *values;
@property(nonatomic) NSUInteger writeCount;
+ (instancetype)standardUserDefaults;
@end

@interface MLTestStatusItem : NSObject
@property(nonatomic) CGFloat length;
@property(nonatomic) CGFloat initialLength;
@property(nonatomic) CGFloat lengthWhenNamed;
@property(nonatomic) BOOL wasSizedBeforeNamed;
@property(nonatomic) BOOL wasSizedBeforeImage;
@property(nonatomic) NSStatusItemBehavior behavior;
@property(nonatomic, getter=isVisible) BOOL visible;
@property(nonatomic, copy) NSString *autosaveName;
@property(nonatomic, strong) NSMenu *menu;
@property(nonatomic, strong) NSButton *button;
@end
@implementation MLTestStatusItem
- (void)setAutosaveName:(NSString *)autosaveName {
    _autosaveName = [autosaveName copy];
    self.lengthWhenNamed = self.length;
}
- (void)setLength:(CGFloat)length {
    _length = length;
    if (length != 0) {
        self.wasSizedBeforeNamed = self.wasSizedBeforeNamed || self.autosaveName.length == 0;
        self.wasSizedBeforeImage = self.wasSizedBeforeImage || self.button.image == nil;
    }
}
@end

@interface MLTestStatusBar : NSObject
@property(nonatomic) NSUInteger creationCount;
+ (instancetype)systemStatusBar;
- (NSStatusItem *)statusItemWithLength:(CGFloat)length;
@end
@implementation MLTestStatusBar
+ (instancetype)systemStatusBar {
    static MLTestStatusBar *bar;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ bar = [[MLTestStatusBar alloc] init]; });
    return bar;
}
- (NSStatusItem *)statusItemWithLength:(CGFloat)length {
    self.creationCount++;
    MLTestStatusItem *item = [[MLTestStatusItem alloc] init];
    item.initialLength = length;
    item.length = length;
    // NSButton provides the real AppKit image, view, accessibility, and layout
    // behavior used by the coordinator, without attaching to NSStatusBar.
    item.button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 24, 24)];
    return (NSStatusItem *)(id)item;
}
@end

MLAudioDevice *MLTestCurrentInput(NSError **error);
NSArray<MLAudioDevice *> *MLTestInputDevices(NSError **error);
MLAudioDevice *MLTestDeviceForUID(NSString *uid, NSError **error);
MLAudioDevice *MLTestUniqueBuiltInInput(NSError **error);
BOOL MLTestSetDefaultInputUID(NSString *uid, NSError **error);

#define NSStatusBar MLTestStatusBar
#define NSUserDefaults MLPlacementMemoryDefaults
#define MLAudioCurrentInput MLTestCurrentInput
#define MLAudioInputDevices MLTestInputDevices
#define MLAudioDeviceForUID MLTestDeviceForUID
#define MLAudioSetDefaultInputUID MLTestSetDefaultInputUID
#define MLAudioUniqueBuiltInInput MLTestUniqueBuiltInInput
#define main MLTestProductionEntrypoint
#include "../menu-app/main.m"
#undef main
#undef NSStatusBar
#undef NSUserDefaults
#undef MLAudioCurrentInput
#undef MLAudioInputDevices
#undef MLAudioDeviceForUID
#undef MLAudioSetDefaultInputUID
#undef MLAudioUniqueBuiltInInput

static MLAudioDevice *FakeMicrophone;
static NSUInteger HardwareWriteAttempts;
static NSUInteger CheckCount;

MLAudioDevice *MLTestCurrentInput(NSError **error) { (void)error; return FakeMicrophone; }
NSArray<MLAudioDevice *> *MLTestInputDevices(NSError **error) {
    (void)error;
    return @[FakeMicrophone];
}
MLAudioDevice *MLTestDeviceForUID(NSString *uid, NSError **error) {
    (void)error;
    return [uid isEqualToString:FakeMicrophone.uid] ? FakeMicrophone : nil;
}
MLAudioDevice *MLTestUniqueBuiltInInput(NSError **error) { (void)error; return FakeMicrophone; }
BOOL MLTestSetDefaultInputUID(NSString *uid, NSError **error) {
    (void)uid; (void)error;
    HardwareWriteAttempts++;
    return NO;
}

static void Check(BOOL condition, NSString *message) {
    CheckCount++;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
}

@implementation MLPlacementMemoryDefaults
+ (instancetype)standardUserDefaults {
    static MLPlacementMemoryDefaults *defaults;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ defaults = [[MLPlacementMemoryDefaults alloc] init]; });
    return defaults;
}
- (instancetype)init {
    self = [super init];
    if (self != nil) self.values = [NSMutableDictionary dictionary];
    return self;
}
- (id)objectForKey:(NSString *)key { return self.values[key]; }
- (void)setObject:(id)value forKey:(NSString *)key {
    self.writeCount++;
    self.values[key] = value;
}
@end

static void TestPlacementRepair(void) {
    MLPlacementMemoryDefaults *defaults = [[MLPlacementMemoryDefaults alloc] init];
    NSString *name = @"io.github.liuzhengyi.miclock";
    NSString *key = [@"NSStatusItem Preferred Position " stringByAppendingString:name];
    NSString *otherKey = @"NSStatusItem Preferred Position another.app";
    defaults.values[otherKey] = @784;
    Check(MLStatusPlacementPrepareDefaults(defaults, name, 645) &&
          [defaults.values[key] isEqual:@0], @"missing own preferred position is seeded to zero");
    NSUInteger writes = defaults.writeCount;
    Check(!MLStatusPlacementPrepareDefaults(defaults, name, 645) && defaults.writeCount == writes,
          @"valid zero position remains unchanged without repeated writes");
    defaults.values[key] = @128;
    Check(!MLStatusPlacementPrepareDefaults(defaults, name, 645) &&
          [defaults.values[key] isEqual:@128], @"visible saved position is preserved");
    defaults.values[key] = @784;
    Check(MLStatusPlacementPrepareDefaults(defaults, name, 645) &&
          [defaults.values[key] isEqual:@0], @"notch-obscured position is repaired for measured right safe area");
    defaults.values[key] = @784;
    Check(!MLStatusPlacementPrepareDefaults(defaults, name, 1470) &&
          [defaults.values[key] isEqual:@784], @"same position is preserved on a wide ordinary screen");
    defaults.values[key] = @(-1);
    Check(MLStatusPlacementPrepareDefaults(defaults, name, 645) &&
          [defaults.values[key] isEqual:@0], @"negative position is repaired");
    defaults.values[key] = @"784";
    Check(MLStatusPlacementPrepareDefaults(defaults, name, 645) &&
          [defaults.values[key] isEqual:@0], @"wrong-type position is repaired instead of coercing text");
    defaults.values[key] = @(NAN);
    Check(MLStatusPlacementPrepareDefaults(defaults, name, 645) &&
          [defaults.values[key] isEqual:@0], @"non-finite position is repaired");
    defaults.values[key] = @(INFINITY);
    Check(MLStatusPlacementPrepareDefaults(defaults, name, 645) &&
          [defaults.values[key] isEqual:@0], @"infinite position is repaired");
    defaults.values[key] = @607;
    Check(!MLStatusPlacementPrepareDefaults(defaults, name, 645) &&
          [defaults.values[key] isEqual:@607], @"right-safe-area boundary reserves the complete host width");
    defaults.values[key] = @607.5;
    Check(MLStatusPlacementPrepareDefaults(defaults, name, 645) &&
          [defaults.values[key] isEqual:@0], @"position beyond the host-safe boundary is repaired");
    defaults.values[key] = @784;
    Check(!MLStatusPlacementPrepareDefaults(defaults, name, 0) &&
          [defaults.values[key] isEqual:@784], @"unknown display width cannot erase a valid saved position");
    Check(!MLStatusPlacementPrepareDefaults(defaults, name, NAN) &&
          [defaults.values[key] isEqual:@784], @"invalid display measurement cannot erase a valid position");
    writes = defaults.writeCount;
    Check(!MLStatusPlacementPrepareDefaults(defaults, @"", 645) && defaults.writeCount == writes,
          @"missing autosave identity cannot write a generic AppKit key");
    Check(!MLStatusPlacementPrepareDefaults(nil, name, 645), @"missing defaults store cannot be written");
    Check(defaults.values.count == 2 && [defaults.values[otherKey] isEqual:@784],
          @"repair touches only the explicitly supplied own-item key");
}

@interface MLStatusItemTestDelegate : MLAppDelegate
@end
@implementation MLStatusItemTestDelegate
- (void)rebuildMenu {
    // The production menu graph is covered by test-enforcement.m. Avoid login
    // service and analytics side effects while retaining real icon refresh.
    self.statusItem.menu = self.statusMenu;
    [self updateStatusIcon];
}
@end

static NSUInteger NontransparentPixels(NSImage *image) {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
    if (bitmap == nil) return 0;
    NSUInteger count = 0;
    for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) {
        for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
            if ([bitmap colorAtX:x y:y].alphaComponent > 0.1) count++;
        }
    }
    return count;
}

int main(void) {
    @autoreleasepool {
        NSString *override = NSProcessInfo.processInfo.environment[@"MICLOCK_SUPPORT_DIR"];
        Check(override.isAbsolutePath && [override containsString:@"miclock-tests."],
              @"requires isolated temporary configuration");
        TestPlacementRepair();
        [NSApplication sharedApplication];
        FakeMicrophone = [[MLAudioDevice alloc] init];
        FakeMicrophone.uid = @"fake-status-built-in";
        FakeMicrophone.name = @"Fake built-in microphone";
        FakeMicrophone.transportType = kAudioDeviceTransportTypeBuiltIn;
        Check(MLSaveConfiguration(@{MLConfigTargetUIDKey:FakeMicrophone.uid,
            MLConfigTargetNameKey:FakeMicrophone.name, MLConfigEnabledKey:@NO}, NULL),
            @"configuration fixture is isolated and locking is paused");
        Check(MLSaveHealth(@{@"status":@"disabled"}, NULL), @"health fixture is isolated");

        MLStatusItemTestDelegate *delegate = [[MLStatusItemTestDelegate alloc] init];
        [delegate createStatusItem];
        NSStatusItem *original = delegate.statusItem;
        MLStatusBadgeView *badge = delegate.badgeView;
        NSMenu *menu = delegate.statusMenu;
        MLTestStatusItem *recordedItem = (MLTestStatusItem *)(id)original;
        Check(recordedItem.initialLength == 0 && recordedItem.lengthWhenNamed == 0 &&
              original.length == NSSquareStatusItemLength && !recordedItem.wasSizedBeforeNamed &&
              !recordedItem.wasSizedBeforeImage,
              @"item is named and painted while zero-width before normal square sizing");
        Check(original != nil && original.button.image != nil && original.isVisible,
              @"initial creation attaches a nonempty icon to a visible item model");
        Check(original.menu == menu && original.behavior == 0,
              @"status item retains its menu and cannot terminate through removal");
        Check(original.button.image.isTemplate && NontransparentPixels(original.button.image) > 10,
              @"real microphone template contains visible ink, not an empty image");
        Check(badge != nil && [badge hitTest:NSMakePoint(4, 4)] == nil,
              @"badge hit testing cannot intercept status-button clicks");

        [delegate createStatusItem];
        Check(delegate.statusItem == original && delegate.badgeView == badge && delegate.statusMenu == menu,
              @"repeated creation preserves item, badge, and menu identity");
        Check(MLTestStatusBar.systemStatusBar.creationCount == 1 && delegate.statusItem.button.image != nil,
              @"repeated creation does not allocate a second item or erase its image");

        NSString *signature = [delegate.lastIconSignature copy];
        delegate.statusItem.button.image = nil;
        [delegate updateStatusIcon];
        Check(delegate.statusItem.button.image != nil && [delegate.lastIconSignature isEqualToString:signature],
              @"missing image is recovered even when hardware and health signature are unchanged");

        original.visible = NO;
        [delegate applicationDidBecomeActive:[NSNotification notificationWithName:NSApplicationDidBecomeActiveNotification
                                                                           object:NSApp]];
        Check(delegate.statusItem == original && original.isVisible && original.button.image != nil,
              @"activation restores visibility without replacing the retained item");

        // Simulate item recovery without changing configuration or signature.
        delegate.statusItem = nil;
        [delegate createStatusItem];
        Check(delegate.statusItem != nil && delegate.statusItem != original &&
              delegate.statusItem.button.image != nil && delegate.statusItem.isVisible &&
              MLTestStatusBar.systemStatusBar.creationCount == 2,
              @"recreated item receives an icon despite the cached unchanged state");
        Check(NontransparentPixels(delegate.statusItem.button.image) > 10,
              @"recovery uses the real nonempty microphone renderer");
        Check(![delegate applicationShouldTerminateAfterLastWindowClosed:NSApp],
              @"closing the last window does not request application termination");
        Check(HardwareWriteAttempts == 0, @"test never changes a microphone input");
        printf("Status item model/rendering tests passed: %lu checks. No real menu-bar item or window was installed.\n",
               (unsigned long)CheckCount);
    }
    return 0;
}
