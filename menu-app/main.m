#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <unistd.h>

@interface MLCommandResult : NSObject
@property(nonatomic) int status;
@property(nonatomic, copy) NSString *output;
@end

@implementation MLCommandResult
@end

typedef NS_ENUM(NSUInteger, MLInputKind) {
    MLInputKindBuiltIn,
    MLInputKindBluetooth,
    MLInputKindOther,
    MLInputKindUnavailable
};

@interface MLStatusBadgeView : NSView
@property(nonatomic, strong) NSColor *badgeColor;
@property(nonatomic, copy) NSString *badgeText;
@end

@implementation MLStatusBadgeView

- (BOOL)isOpaque {
    return NO;
}

- (NSView *)hitTest:(NSPoint)point {
    // Keep the whole status item clickable; this view is visual only.
    return nil;
}

- (BOOL)isAccessibilityElement {
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSGraphicsContext.currentContext.shouldAntialias = YES;

    NSRect badgeRect = NSInsetRect(self.bounds, 0.2, 0.2);
    [(self.badgeColor ?: NSColor.systemRedColor) setFill];
    [[NSBezierPath bezierPathWithOvalInRect:badgeRect] fill];

    [[NSColor.whiteColor colorWithAlphaComponent:0.95] setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(badgeRect, 0.35, 0.35)];
    border.lineWidth = 0.8;
    [border stroke];

    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:6.4 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: NSColor.whiteColor,
        NSParagraphStyleAttributeName: paragraph
    };
    NSString *text = self.badgeText ?: @"!";
    NSSize textSize = [text sizeWithAttributes:attributes];
    NSPoint textOrigin = NSMakePoint(
        round((NSWidth(self.bounds) - textSize.width) / 2.0),
        round((NSHeight(self.bounds) - textSize.height) / 2.0)
    );
    [text drawAtPoint:textOrigin withAttributes:attributes];
}

@end

static MLCommandResult *MLRunCommand(NSString *executable, NSArray<NSString *> *arguments) {
    MLCommandResult *result = [[MLCommandResult alloc] init];
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [NSPipe pipe];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = arguments;
    task.standardOutput = pipe;
    task.standardError = pipe;

    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"HOME"] = NSHomeDirectory();
    task.environment = environment;

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        result.status = 127;
        result.output = error.localizedDescription ?: @"无法启动命令";
        return result;
    }

    [task waitUntilExit];
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    result.status = task.terminationStatus;
    result.output = [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return result;
}

@interface MLAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) MLStatusBadgeView *badgeView;
@property(nonatomic, strong) NSMenu *statusMenu;
@property(nonatomic, strong) NSTimer *refreshTimer;
@property(nonatomic, copy) NSString *miclockPath;
@property(nonatomic, copy) NSString *switchAudioPath;
@property(nonatomic, copy) NSString *targetFile;
@property(nonatomic, copy) NSString *serviceName;
@end

@implementation MLAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    NSString *home = NSHomeDirectory();
    self.miclockPath = [home stringByAppendingPathComponent:@".local/bin/miclock"];
    NSString *bundledSwitch = [NSBundle.mainBundle pathForResource:@"SwitchAudioSource"
                                                             ofType:nil
                                                        inDirectory:@"bin"];
    NSArray<NSString *> *switchCandidates = @[
        bundledSwitch ?: @"",
        @"/opt/homebrew/opt/switchaudio-osx/SwitchAudioSource",
        @"/opt/homebrew/bin/SwitchAudioSource",
        @"/usr/local/bin/SwitchAudioSource"
    ];
    for (NSString *candidate in switchCandidates) {
        if ([NSFileManager.defaultManager isExecutableFileAtPath:candidate]) {
            self.switchAudioPath = candidate;
            break;
        }
    }
    if (self.switchAudioPath.length == 0) self.switchAudioPath = @"/opt/homebrew/bin/SwitchAudioSource";
    self.targetFile = [home stringByAppendingPathComponent:@".config/mic-input-lock/device-name"];
    self.serviceName = [NSString stringWithFormat:@"gui/%u/com.user.mic-input-lock", getuid()];

    self.statusMenu = [[NSMenu alloc] initWithTitle:@"麦克风锁定"];
    self.statusMenu.delegate = self;
    self.statusMenu.autoenablesItems = NO;

    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.autosaveName = @"com.user.mic-input-lock-menu";
    self.statusItem.menu = self.statusMenu;

    NSButton *statusButton = self.statusItem.button;
    statusButton.imagePosition = NSImageOnly;
    statusButton.title = @"";

    // Keep the microphone as a native template image so macOS can tint it for
    // the current menu-bar background. The colored device badge is a separate
    // overlay and therefore keeps its M/A/O/! state color.
    self.badgeView = [[MLStatusBadgeView alloc] initWithFrame:NSZeroRect];
    self.badgeView.translatesAutoresizingMaskIntoConstraints = NO;
    [statusButton addSubview:self.badgeView];
    [NSLayoutConstraint activateConstraints:@[
        [self.badgeView.widthAnchor constraintEqualToConstant:9.0],
        [self.badgeView.heightAnchor constraintEqualToConstant:9.0],
        [self.badgeView.trailingAnchor constraintEqualToAnchor:statusButton.trailingAnchor constant:-1.5],
        [self.badgeView.bottomAnchor constraintEqualToAnchor:statusButton.bottomAnchor constant:1.5]
    ]];

    [self updateStatusIcon];
    [self rebuildMenu];
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                         target:self
                                                       selector:@selector(refreshTimerFired:)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.refreshTimer invalidate];
}

- (void)menuWillOpen:(NSMenu *)menu {
    [self rebuildMenu];
}

- (void)refreshTimerFired:(NSTimer *)timer {
    [self updateStatusIcon];
}

- (BOOL)isLockRunning {
    return MLRunCommand(@"/bin/launchctl", @[@"print", self.serviceName]).status == 0;
}

- (NSDictionary<NSString *, NSString *> *)currentInputMetadata {
    MLCommandResult *result = MLRunCommand(
        self.switchAudioPath, @[@"-c", @"-t", @"input", @"-f", @"json"]
    );
    if (result.status == 0 && result.output.length > 0) {
        NSData *data = [result.output dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *record = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([record isKindOfClass:NSDictionary.class]) return record;
    }
    return @{@"name": @"不可用", @"uid": @""};
}

- (NSString *)currentInput {
    NSString *name = [self currentInputMetadata][@"name"];
    return name.length > 0 ? name : @"不可用";
}

- (NSString *)configuredTarget {
    NSError *error = nil;
    NSString *value = [NSString stringWithContentsOfFile:self.targetFile
                                                encoding:NSUTF8StringEncoding
                                                   error:&error];
    if (value == nil) return @"";
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (NSArray<NSString *> *)inputDevices {
    MLCommandResult *result = MLRunCommand(self.switchAudioPath, @[@"-a", @"-t", @"input"]);
    if (result.status != 0 || result.output.length == 0) return @[];

    NSMutableArray<NSString *> *devices = [NSMutableArray array];
    for (NSString *line in [result.output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *device = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (device.length > 0) [devices addObject:device];
    }
    return devices;
}

- (BOOL)isBluetoothInputUID:(NSString *)uid {
    if (![uid hasSuffix:@":input"] || uid.length < 23) return NO;
    NSString *prefix = [uid substringToIndex:uid.length - @":input".length];
    NSArray<NSString *> *parts = [prefix componentsSeparatedByString:@"-"];
    if (parts.count != 6) return NO;
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef"];
    for (NSString *part in parts) {
        if (part.length != 2 || [[part stringByTrimmingCharactersInSet:hex] length] != 0) return NO;
    }
    return YES;
}

- (MLInputKind)inputKindForMetadata:(NSDictionary<NSString *, NSString *> *)metadata {
    NSString *name = metadata[@"name"] ?: @"";
    NSString *uid = metadata[@"uid"] ?: @"";
    NSString *lowerName = name.lowercaseString;

    if ([uid isEqualToString:@"BuiltInMicrophoneDevice"] ||
        ([lowerName containsString:@"macbook"] && [name containsString:@"麦克风"])) {
        return MLInputKindBuiltIn;
    }
    if ([lowerName containsString:@"airpods"] || [self isBluetoothInputUID:uid]) {
        return MLInputKindBluetooth;
    }
    if ([name isEqualToString:@"不可用"] || name.length == 0) {
        return MLInputKindUnavailable;
    }
    return MLInputKindOther;
}

- (NSColor *)badgeColorForInputKind:(MLInputKind)kind {
    switch (kind) {
        case MLInputKindBuiltIn: return NSColor.systemBlueColor;
        case MLInputKindBluetooth: return NSColor.systemTealColor;
        case MLInputKindOther: return NSColor.systemOrangeColor;
        case MLInputKindUnavailable: return NSColor.systemRedColor;
    }
}

- (NSString *)badgeTextForInputKind:(MLInputKind)kind {
    switch (kind) {
        case MLInputKindBuiltIn: return @"M";
        case MLInputKindBluetooth: return @"A";
        case MLInputKindOther: return @"O";
        case MLInputKindUnavailable: return @"!";
    }
}

- (NSImage *)statusTemplateImageLocked:(BOOL)locked
                    accessibilityLabel:(NSString *)accessibilityLabel {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(20.0, 18.0)];
    [image lockFocus];
    NSGraphicsContext.currentContext.shouldAntialias = YES;

    // A template image uses opacity as its mask. AppKit supplies the correct
    // white or dark tint for the live menu bar; paused mode stays slightly softer.
    NSColor *ink = [NSColor colorWithWhite:0.0 alpha:(locked ? 1.0 : 0.62)];
    [ink setStroke];

    // Stable MicLock mark: the microphone silhouette never changes with devices.
    // A filled capsule means automatic correction is active; an outline means paused.
    NSRect capsuleRect = NSMakeRect(5.0, 7.2, 7.2, 9.5);
    NSBezierPath *capsule = [NSBezierPath bezierPathWithRoundedRect:capsuleRect
                                                            xRadius:3.6
                                                            yRadius:3.6];
    capsule.lineWidth = 1.45;
    if (locked) {
        [ink setFill];
        [capsule fill];
    } else {
        [capsule stroke];
    }

    NSBezierPath *yoke = [NSBezierPath bezierPath];
    yoke.lineWidth = 1.45;
    yoke.lineCapStyle = NSLineCapStyleRound;
    yoke.lineJoinStyle = NSLineJoinStyleRound;
    [yoke moveToPoint:NSMakePoint(3.3, 10.5)];
    [yoke curveToPoint:NSMakePoint(8.6, 5.0)
         controlPoint1:NSMakePoint(3.3, 7.1)
         controlPoint2:NSMakePoint(5.6, 5.0)];
    [yoke curveToPoint:NSMakePoint(13.9, 10.5)
         controlPoint1:NSMakePoint(11.6, 5.0)
         controlPoint2:NSMakePoint(13.9, 7.1)];
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
    image.accessibilityDescription = accessibilityLabel;
    return image;
}

- (void)updateStatusIcon {
    BOOL running = [self isLockRunning];
    NSDictionary<NSString *, NSString *> *metadata = [self currentInputMetadata];
    NSString *current = metadata[@"name"] ?: @"不可用";
    MLInputKind kind = [self inputKindForMetadata:metadata];
    NSString *lockState = running ? @"自动锁定已开启" : @"自动锁定已关闭";
    NSString *description = [NSString stringWithFormat:@"当前输入：%@；%@", current, lockState];
    NSImage *image = [self statusTemplateImageLocked:running accessibilityLabel:description];
    self.statusItem.button.image = image;
    self.statusItem.button.imagePosition = NSImageOnly;
    self.statusItem.button.title = @"";
    self.statusItem.button.toolTip = description;
    [self.statusItem.button setAccessibilityLabel:@"MicLock"];
    [self.statusItem.button setAccessibilityValue:description];
    self.badgeView.badgeColor = [self badgeColorForInputKind:kind];
    self.badgeView.badgeText = [self badgeTextForInputKind:kind];
    [self.badgeView setNeedsDisplay:YES];
}

- (void)addDisabledItem:(NSString *)title {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    item.enabled = NO;
    [self.statusMenu addItem:item];
}

- (NSMenuItem *)actionItemWithTitle:(NSString *)title action:(SEL)action {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    item.enabled = YES;
    return item;
}

- (void)rebuildMenu {
    [self.statusMenu removeAllItems];

    BOOL running = [self isLockRunning];
    NSString *current = [self currentInput];
    NSString *target = [self configuredTarget];

    [self addDisabledItem:[NSString stringWithFormat:@"当前输入：%@", current]];
    if (target.length > 0) {
        [self addDisabledItem:[NSString stringWithFormat:@"锁定目标：%@", target]];
    }
    [self.statusMenu addItem:NSMenuItem.separatorItem];

    NSString *toggleTitle = running ? @"自动锁定：已开启" : @"自动锁定：已关闭";
    NSMenuItem *toggleItem = [self actionItemWithTitle:toggleTitle action:@selector(toggleLock:)];
    toggleItem.state = running ? NSControlStateValueOn : NSControlStateValueOff;
    toggleItem.image = [NSImage imageWithSystemSymbolName:(running ? @"mic.fill" : @"mic")
                                  accessibilityDescription:toggleTitle];
    [self.statusMenu addItem:toggleItem];

    [self.statusMenu addItem:NSMenuItem.separatorItem];
    [self addDisabledItem:@"默认输入设备"];

    NSArray<NSString *> *devices = [self inputDevices];
    if (devices.count == 0) {
        [self addDisabledItem:@"没有可用设备"];
    } else {
        for (NSString *device in devices) {
            NSString *title = device;
            if ([device isEqualToString:target]) {
                title = [device stringByAppendingString:(running ? @"  （锁定）" : @"  （上次锁定）")];
            }
            NSMenuItem *item = [self actionItemWithTitle:title action:@selector(selectDevice:)];
            item.representedObject = device;
            item.state = [device isEqualToString:current] ? NSControlStateValueOn : NSControlStateValueOff;
            [self.statusMenu addItem:item];
        }
    }

    [self.statusMenu addItem:NSMenuItem.separatorItem];

    NSMenuItem *refresh = [self actionItemWithTitle:@"刷新" action:@selector(refreshMenu:)];
    refresh.keyEquivalent = @"r";
    [self.statusMenu addItem:refresh];

    NSMenuItem *quitIcon = [self actionItemWithTitle:@"退出菜单栏图标（保持当前锁定）"
                                              action:@selector(quitIcon:)];
    quitIcon.keyEquivalent = @"q";
    [self.statusMenu addItem:quitIcon];

    [self.statusMenu addItem:[self actionItemWithTitle:@"停止锁定并退出（恢复系统行为）"
                                                action:@selector(stopAndQuit:)]];
    [self updateStatusIcon];
}

- (BOOL)runMiclock:(NSArray<NSString *> *)arguments {
    MLCommandResult *result = MLRunCommand(self.miclockPath, arguments);
    if (result.status != 0) {
        [self showError:(result.output.length > 0 ? result.output : @"命令执行失败")];
        return NO;
    }
    return YES;
}

- (void)showError:(NSString *)message {
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"麦克风操作失败";
    alert.informativeText = message;
    [alert addButtonWithTitle:@"好"];
    [alert runModal];
}

- (void)toggleLock:(NSMenuItem *)sender {
    [self runMiclock:@[[self isLockRunning] ? @"off" : @"on"]];
    [self rebuildMenu];
}

- (void)selectDevice:(NSMenuItem *)sender {
    NSString *device = [sender.representedObject isKindOfClass:NSString.class]
        ? sender.representedObject : nil;
    if (device == nil) return;
    [self runMiclock:@[@"use", device]];
    [self rebuildMenu];
}

- (void)refreshMenu:(NSMenuItem *)sender {
    [self rebuildMenu];
}

- (void)quitIcon:(NSMenuItem *)sender {
    [NSApp terminate:nil];
}

- (void)stopAndQuit:(NSMenuItem *)sender {
    if ([self runMiclock:@[@"off"]]) [NSApp terminate:nil];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        MLAppDelegate *delegate = [[MLAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
