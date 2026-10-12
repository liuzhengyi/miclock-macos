#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// Sparkle owns authenticated download, replacement and restart. MicLock only
// supplies explicit user actions and bundled release notes.
@interface MLUpdateController : NSObject
@property(nonatomic, readonly) BOOL canCheckForUpdates;
- (void)checkForUpdates:(nullable id)sender;
- (void)showReleaseNotes:(nullable id)sender;
@end

FOUNDATION_EXPORT BOOL MLUpdateDownloadURLIsAllowed(NSURL *url);

NS_ASSUME_NONNULL_END
