#import "MLStatusWindow.h"
#import "MLState.h"
#import "MLAnalytics.h"

static NSString *MLSWL(NSString *key) {
    return [NSBundle.mainBundle localizedStringForKey:key value:key table:nil];
}

@interface MLStatusWindowController ()
@property(nonatomic, strong) NSTextField *currentInputLabel;
@property(nonatomic, strong) NSTextField *healthLabel;
@property(nonatomic, strong) NSPopUpButton *targetPicker;
@property(nonatomic, strong) NSButton *automaticLockButton;
@property(nonatomic, strong) NSButton *analyticsButton;
@property(nonatomic, copy) NSString *targetListSignature;
@end

@implementation MLStatusWindowController

- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (NSStackView *)verticalGroup:(NSArray<NSView *> *)views spacing:(CGFloat)spacing {
    NSStackView *group = [NSStackView stackViewWithViews:views];
    group.orientation = NSUserInterfaceLayoutOrientationVertical;
    group.alignment = NSLayoutAttributeLeading;
    group.spacing = spacing;
    for (NSView *view in views) {
        [view.widthAnchor constraintEqualToAnchor:group.widthAnchor].active = YES;
    }
    return group;
}

- (NSButton *)actionButton:(NSString *)title action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    return button;
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 610, 570)
                 styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                   backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:window];
    if (self == nil) return nil;
    window.title = MLSWL(@"MicLock Status and Settings");
    window.releasedWhenClosed = NO;
    [window center];

    NSTextField *title = [self label:MLSWL(@"Voice Input Companion")
        font:[NSFont systemFontOfSize:22 weight:NSFontWeightSemibold] color:NSColor.labelColor];
    NSString *version = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] != nil
        ? NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] : @"";
    NSTextField *subtitle = [self label:[NSString stringWithFormat:@"MicLock %@", version]
        font:[NSFont systemFontOfSize:12] color:NSColor.secondaryLabelColor];
    NSStackView *header = [self verticalGroup:@[title, subtitle] spacing:5];

    NSTextField *currentTitle = [self label:MLSWL(@"Current microphone")
        font:[NSFont systemFontOfSize:12] color:NSColor.secondaryLabelColor];
    self.currentInputLabel = [self label:MLSWL(@"Unavailable")
        font:[NSFont systemFontOfSize:20 weight:NSFontWeightMedium] color:NSColor.labelColor];
    self.currentInputLabel.selectable = YES;
    [self.currentInputLabel setAccessibilityLabel:MLSWL(@"Current microphone")];
    self.healthLabel = [self label:@""
        font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium] color:NSColor.secondaryLabelColor];
    NSStackView *currentGroup = [self verticalGroup:@[currentTitle, self.currentInputLabel, self.healthLabel] spacing:6];

    NSTextField *targetTitle = [self label:MLSWL(@"Target microphone")
        font:[NSFont systemFontOfSize:12] color:NSColor.secondaryLabelColor];
    self.targetPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.targetPicker.target = self;
    self.targetPicker.action = @selector(targetChanged:);
    self.targetPicker.menu.autoenablesItems = NO;
    [self.targetPicker setAccessibilityLabel:MLSWL(@"Target microphone")];
    NSStackView *targetGroup = [self verticalGroup:@[targetTitle, self.targetPicker] spacing:6];

    self.automaticLockButton = [NSButton checkboxWithTitle:MLSWL(@"Automatic Lock")
        target:self action:@selector(automaticLockChanged:)];
    NSTextField *hint = [NSTextField wrappingLabelWithString:
        MLSWL(@"Choose System Default in your voice app. Your headphones can continue playing audio.")];
    hint.font = [NSFont systemFontOfSize:12];
    hint.textColor = NSColor.secondaryLabelColor;
    NSTextField *menuHint = [NSTextField wrappingLabelWithString:MLSWL(@"MicLock stays in the top menu bar. Close this window to keep it running; open MicLock again to return here.")];
    menuHint.font = [NSFont systemFontOfSize:12];
    menuHint.textColor = NSColor.secondaryLabelColor;

    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.boxType = NSBoxSeparator;
    NSStackView *actions = [NSStackView stackViewWithViews:@[
        [self actionButton:MLSWL(@"Quick Start…") action:@selector(openQuickStart:)],
        [self actionButton:MLSWL(@"Report an Issue…") action:@selector(reportIssue:)],
    ]];
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.spacing = 10;
    NSStackView *maintenance = [NSStackView stackViewWithViews:@[
        [self actionButton:MLSWL(@"Version History…") action:@selector(versionHistory:)],
        [self actionButton:MLSWL(@"Check for Updates…") action:@selector(checkForUpdates:)],
        [self actionButton:MLSWL(@"Uninstall MicLock…") action:@selector(uninstall:)],
    ]];
    maintenance.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    maintenance.spacing = 10;
    self.analyticsButton = [NSButton checkboxWithTitle:MLSWL(@"Send anonymous usage statistics to help improve MicLock")
        target:self action:@selector(analyticsChanged:)];
    self.analyticsButton.state = MLAnalyticsConsentEnabled(NSUserDefaults.standardUserDefaults)
        ? NSControlStateValueOn : NSControlStateValueOff;
    NSTextField *analyticsHint = [NSTextField wrappingLabelWithString:MLSWL(@"Optional. Counts app starts and successful locking with a random ID; sends no voice, text, account or device identifier. Turn off anytime.")];
    analyticsHint.font = [NSFont systemFontOfSize:11]; analyticsHint.textColor = NSColor.secondaryLabelColor;

    NSStackView *content = [self verticalGroup:@[
        header, currentGroup, targetGroup, self.automaticLockButton, hint, menuHint, separator, actions, maintenance,
        self.analyticsButton, analyticsHint
    ] spacing:18];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [window.contentView addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:24],
        [content.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-24],
        [content.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:24],
        [content.bottomAnchor constraintLessThanOrEqualToAnchor:window.contentView.bottomAnchor constant:-24],
    ]];
    return self;
}

- (void)updateWithCurrentInput:(MLAudioDevice *)current
                configuration:(NSDictionary *)configuration
                       health:(NSDictionary *)health
            healthDisplayName:(NSString *)healthDisplayName
                      devices:(NSArray<MLAudioDevice *> *)devices {
    BOOL enabled = [configuration[MLConfigEnabledKey] boolValue];
    NSString *targetUID = configuration[MLConfigTargetUIDKey] != nil ? configuration[MLConfigTargetUIDKey] : @"";
    NSString *targetName = configuration[MLConfigTargetNameKey] != nil
        ? configuration[MLConfigTargetNameKey] : MLSWL(@"Not configured");
    self.currentInputLabel.stringValue = current.name != nil ? current.name : MLSWL(@"Unavailable");
    self.automaticLockButton.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;

    BOOL targetAvailable = NO;
    NSMutableString *signature = [NSMutableString stringWithFormat:@"%@|%@", targetUID, targetName];
    for (MLAudioDevice *device in devices) {
        if ([device.uid isEqualToString:targetUID]) targetAvailable = YES;
        [signature appendFormat:@"|%@:%@:%@", device.uid, device.name, device.transportLabel];
    }
    NSString *status = health[@"status"] != nil ? health[@"status"] : @"disabled";
    BOOL nominallyHealthy = [status isEqualToString:@"healthy"] || [status isEqualToString:@"corrected"];
    BOOL matching = enabled && nominallyHealthy && current != nil && [current.uid isEqualToString:targetUID];
    NSString *displayName = healthDisplayName;
    if (enabled && targetUID.length > 0 && !targetAvailable) displayName = MLSWL(@"Waiting for target device");
    else if (enabled && nominallyHealthy && !matching) displayName = MLSWL(@"Restoring the selected input");
    self.healthLabel.stringValue = [NSString stringWithFormat:MLSWL(@"Status: %@"), displayName];
    self.healthLabel.textColor = matching ? NSColor.systemGreenColor
        : (enabled ? NSColor.systemOrangeColor : NSColor.secondaryLabelColor);

    if (![signature isEqualToString:self.targetListSignature]) {
        [self.targetPicker removeAllItems];
        if (!targetAvailable) {
            NSString *placeholder = targetUID.length > 0
                ? [NSString stringWithFormat:@"%@ — %@", targetName, MLSWL(@"Unavailable")]
                : MLSWL(@"Choose a lock target");
            [self.targetPicker addItemWithTitle:placeholder];
            self.targetPicker.lastItem.enabled = NO;
            self.targetPicker.lastItem.representedObject = targetUID;
        }
        for (MLAudioDevice *device in devices) {
            [self.targetPicker addItemWithTitle:
                [NSString stringWithFormat:@"%@ — %@", device.name, MLSWL(device.transportLabel)]];
            self.targetPicker.lastItem.representedObject = device.uid;
        }
        self.targetPicker.enabled = devices.count > 0;
        self.targetListSignature = signature;
    }
    // Selection is always read from committed configuration, including after
    // an action failed without changing the device list or saved target.
    for (NSMenuItem *item in self.targetPicker.itemArray) {
        if ([item.representedObject isEqualToString:targetUID]) {
            [self.targetPicker selectItem:item];
            break;
        }
    }
}

- (void)automaticLockChanged:(NSButton *)sender {
    (void)sender;
    if (self.onToggleAutomaticLock != nil) self.onToggleAutomaticLock();
}

- (void)targetChanged:(NSPopUpButton *)sender {
    NSString *uid = [sender.selectedItem.representedObject isKindOfClass:NSString.class]
        ? sender.selectedItem.representedObject : nil;
    if (uid.length > 0 && sender.selectedItem.enabled && self.onSelectTarget != nil) self.onSelectTarget(uid);
}

- (void)openQuickStart:(NSButton *)sender { (void)sender; if (self.onQuickStart != nil) self.onQuickStart(); }
- (void)copyDiagnostics:(NSButton *)sender { (void)sender; if (self.onCopyDiagnostics != nil) self.onCopyDiagnostics(); }
- (void)reportIssue:(NSButton *)sender { (void)sender; if (self.onReportIssue != nil) self.onReportIssue(); }
- (void)versionHistory:(NSButton *)sender { (void)sender; if (self.onVersionHistory != nil) self.onVersionHistory(); }
- (void)checkForUpdates:(NSButton *)sender { (void)sender; if (self.onCheckForUpdates != nil) self.onCheckForUpdates(); }
- (void)uninstall:(NSButton *)sender { (void)sender; if (self.onUninstall != nil) self.onUninstall(); }
- (void)analyticsChanged:(NSButton *)sender {
    if (self.onAnalyticsConsentChanged != nil) self.onAnalyticsConsentChanged(sender.state == NSControlStateValueOn);
}

@end
