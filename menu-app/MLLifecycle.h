#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT BOOL MLUninstallPathIsAllowed(NSURL *bundleURL, NSURL *homeURL);
FOUNDATION_EXPORT NSArray<NSString *> *MLUninstallKnownStateFiles(void);
FOUNDATION_EXPORT NSArray<NSURL *> *MLUninstallStateFilesAtURL(NSURL *directoryURL, NSError **error);

@interface MLLifecycleController : NSObject
@property(nonatomic, copy, nullable) BOOL (^onPrepareForUninstall)(NSError **error);
@property(nonatomic, copy, nullable) void (^onUninstallFailed)(void);
- (void)uninstall:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
