#import "MLGuide.h"
#import <AppKit/AppKit.h>

void MLShowUsageGuide(BOOL recordCompletion) {
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(@"Keep your microphone when you connect headphones.", nil);
    alert.informativeText = NSLocalizedString(@"Quick Start Details", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"Got It", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Open Sound Settings", nil)];
    NSModalResponse response = [alert runModal];
    if (recordCompletion) {
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"MLDidShowQuickStartV311"];
    }
    if (response == NSAlertSecondButtonReturn) {
        [NSWorkspace.sharedWorkspace openURL:
            [NSURL URLWithString:@"x-apple.systempreferences:com.apple.Sound-Settings.extension"]];
    }
}

@interface MLGuideDelegate : NSObject <NSApplicationDelegate>
@end
@implementation MLGuideDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    MLShowUsageGuide(NO);
    [NSApp terminate:nil];
}
@end

int MLRunStandaloneGuide(void) {
    NSApplication *application = NSApplication.sharedApplication;
    MLGuideDelegate *delegate = [[MLGuideDelegate alloc] init];
    application.delegate = delegate;
    [application run];
    return 0;
}
