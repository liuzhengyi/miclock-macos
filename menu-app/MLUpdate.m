#import "MLUpdate.h"
#import <Sparkle/Sparkle.h>

static NSString *MLUL(NSString *key) {
    return [NSBundle.mainBundle localizedStringForKey:key value:key table:nil];
}

BOOL MLUpdateDownloadURLIsAllowed(NSURL *url) {
    if (![url.scheme isEqualToString:@"https"] || url.user.length > 0 ||
        url.password.length > 0 || url.fragment.length > 0 || url.query.length > 0 ||
        (url.port != nil && url.port.integerValue != 443) ||
        ![url.host.lowercaseString isEqualToString:@"ecnkfnba0c1r.feishuapp.com"]) return NO;
    NSString *prefix = @"/app/app_17ftjhzb3vs/downloads/";
    NSString *path = url.path;
    if (![path hasPrefix:prefix]) return NO;
    NSString *filename = [path substringFromIndex:prefix.length];
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:
        @"^MicLock-[0-9]+\\.[0-9]+\\.[0-9]+\\.(dmg|zip)$" options:0 error:nil];
    return [pattern numberOfMatchesInString:filename options:0 range:NSMakeRange(0, filename.length)] == 1;
}

@interface MLUpdateController () <SPUUpdaterDelegate>
@property(nonatomic, strong) SPUStandardUpdaterController *sparkleController;
@property(nonatomic, strong) NSWindowController *notesController;
@end

@implementation MLUpdateController
- (instancetype)init {
    self = [super init];
    if (self != nil) {
        self.sparkleController = [[SPUStandardUpdaterController alloc]
            initWithStartingUpdater:YES updaterDelegate:self userDriverDelegate:nil];
    }
    return self;
}
- (BOOL)canCheckForUpdates { return self.sparkleController.updater.canCheckForUpdates; }
- (void)checkForUpdates:(id)sender {
    [NSApp activateIgnoringOtherApps:YES];
    [self.sparkleController checkForUpdates:sender];
}
- (BOOL)updaterShouldPromptForPermissionToCheckForUpdates:(SPUUpdater *)updater {
    (void)updater;
    // This release uses explicit checks. It never opts users into a background
    // update or system-profile transmission at launch.
    return NO;
}
- (NSArray<NSString *> *)allowedSystemProfileKeysForUpdater:(SPUUpdater *)updater {
    (void)updater;
    return @[];
}
- (BOOL)updater:(SPUUpdater *)updater shouldProceedWithUpdate:(SUAppcastItem *)item
         updateCheck:(SPUUpdateCheck)updateCheck error:(NSError **)error {
    (void)updater; (void)updateCheck;
    if (item.fileURL != nil && MLUpdateDownloadURLIsAllowed(item.fileURL)) return YES;
    if (error != NULL) *error = [NSError errorWithDomain:@"io.github.liuzhengyi.miclock.update"
        code:1 userInfo:@{NSLocalizedDescriptionKey:MLUL(@"The update download address is not trusted.")}];
    return NO;
}
- (void)showReleaseNotes:(id)sender {
    (void)sender;
    if (self.notesController == nil) {
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 570, 440)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
            backing:NSBackingStoreBuffered defer:NO];
        window.title = MLUL(@"Version History");
        window.releasedWhenClosed = NO;
        [window center];
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:window.contentView.bounds];
        scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        scroll.hasVerticalScroller = YES;
        NSTextView *text = [[NSTextView alloc] initWithFrame:scroll.bounds];
        text.editable = NO;
        text.font = [NSFont systemFontOfSize:13];
        text.textContainerInset = NSMakeSize(24, 20);
        text.autoresizingMask = NSViewWidthSizable;
        text.textContainer.widthTracksTextView = YES;
        NSURL *notesURL = [NSBundle.mainBundle URLForResource:@"ReleaseNotes" withExtension:@"txt"];
        NSString *notes = notesURL != nil
            ? [NSString stringWithContentsOfURL:notesURL encoding:NSUTF8StringEncoding error:nil] : nil;
        text.string = notes != nil ? notes : MLUL(@"Release notes are unavailable.");
        scroll.documentView = text;
        [window.contentView addSubview:scroll];
        self.notesController = [[NSWindowController alloc] initWithWindow:window];
    }
    [self.notesController showWindow:nil];
    [self.notesController.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}
@end
