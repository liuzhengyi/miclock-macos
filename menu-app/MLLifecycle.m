#import "MLLifecycle.h"
#import <ServiceManagement/ServiceManagement.h>
#import <unistd.h>

static NSString *MLLL(NSString *key) {
    return [NSBundle.mainBundle localizedStringForKey:key value:key table:nil];
}
static NSError *MLLifecycleError(NSString *message) {
    return [NSError errorWithDomain:@"io.github.liuzhengyi.miclock.lifecycle" code:1
        userInfo:@{NSLocalizedDescriptionKey:message}];
}

BOOL MLUninstallPathIsAllowed(NSURL *bundleURL, NSURL *homeURL) {
    if (!bundleURL.isFileURL || !homeURL.isFileURL || !bundleURL.path.isAbsolutePath) return NO;
    NSURL *standard = bundleURL.URLByStandardizingPath;
    if (![standard.lastPathComponent isEqualToString:@"MicLock.app"]) return NO;
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:standard.path error:nil];
    if ([attributes[NSFileType] isEqualToString:NSFileTypeSymbolicLink]) return NO;
    // Do not follow an app symlink or an Applications alias to an unrelated
    // location. We recycle only the exact main bundle in a standard location.
    if (![standard.path isEqualToString:standard.URLByResolvingSymlinksInPath.path]) return NO;
    NSString *parent = standard.URLByDeletingLastPathComponent.path;
    NSString *personal = [homeURL.URLByStandardizingPath.path stringByAppendingPathComponent:@"Applications"];
    return [parent isEqualToString:@"/Applications"] || [parent isEqualToString:personal];
}

NSArray<NSString *> *MLUninstallKnownStateFiles(void) {
    return @[@"config.plist", @"health.plist", @"config.lock", @"health.lock",
             @"feedback-draft.json", @"feedback-latest.json"];
}

NSArray<NSURL *> *MLUninstallStateFilesAtURL(NSURL *directoryURL, NSError **error) {
    NSFileManager *manager = NSFileManager.defaultManager;
    if (!directoryURL.isFileURL || ![directoryURL.path isEqualToString:
        directoryURL.URLByStandardizingPath.URLByResolvingSymlinksInPath.path]) {
        if (error != NULL) *error = MLLifecycleError(MLLL(@"MicLock settings contain a link and were preserved."));
        return @[];
    }
    BOOL isDirectory = NO;
    if (![manager fileExistsAtPath:directoryURL.path isDirectory:&isDirectory]) return @[];
    if (!isDirectory) {
        if (error != NULL) *error = MLLifecycleError(MLLL(@"MicLock settings could not be removed."));
        return @[];
    }
    NSMutableArray<NSURL *> *safe = [NSMutableArray array];
    for (NSString *name in MLUninstallKnownStateFiles()) {
        NSURL *file = [directoryURL URLByAppendingPathComponent:name];
        NSDictionary *attributes = [manager attributesOfItemAtPath:file.path error:nil];
        if (attributes == nil) continue;
        if (![attributes[NSFileType] isEqualToString:NSFileTypeRegular] ||
            ![file.path isEqualToString:file.URLByResolvingSymlinksInPath.path]) {
            if (error != NULL) *error = MLLifecycleError(MLLL(@"Some MicLock settings were preserved for safety."));
            continue;
        }
        [safe addObject:file];
    }
    return safe;
}

@implementation MLLifecycleController
- (void)showError:(NSError *)error {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = MLLL(@"Could Not Uninstall MicLock");
    alert.informativeText = error.localizedDescription != nil
        ? error.localizedDescription : MLLL(@"Please move MicLock to the Trash in Finder.");
    [alert addButtonWithTitle:MLLL(@"OK")];
    [alert runModal];
}
- (void)uninstall:(id)sender {
    (void)sender;
    [NSApp activateIgnoringOtherApps:YES];
    NSURL *bundleURL = NSBundle.mainBundle.bundleURL;
    if (!MLUninstallPathIsAllowed(bundleURL, [NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES]) ||
        ![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"io.github.liuzhengyi.miclock"]) {
        [self showError:MLLifecycleError(MLLL(@"Install MicLock in Applications before using in-app uninstall. Otherwise remove this copy in Finder."))];
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = MLLL(@"Uninstall MicLock?");
    alert.informativeText = MLLL(@"MicLock will stop locking, remove its login item, and move this app to the Trash. Your microphone remains available to other apps.");
    [alert addButtonWithTitle:MLLL(@"Cancel")];
    [alert addButtonWithTitle:MLLL(@"Move to Trash")];
    NSButton *clearSettings = [NSButton checkboxWithTitle:MLLL(@"Also remove MicLock settings") target:nil action:nil];
    clearSettings.frame = NSMakeRect(0, 0, 340, 26);
    clearSettings.state = NSControlStateValueOff;
    alert.accessoryView = clearSettings;
    if ([alert runModal] != NSAlertSecondButtonReturn) return;

    NSError *error = nil;
    if (self.onPrepareForUninstall == nil || !self.onPrepareForUninstall(&error)) {
        [self showError:error != nil ? error : MLLifecycleError(MLLL(@"Could Not Disable MicLock"))];
        return;
    }
    SMAppService *service = SMAppService.mainAppService;
    if ((service.status == SMAppServiceStatusEnabled || service.status == SMAppServiceStatusRequiresApproval) &&
        ![service unregisterAndReturnError:&error]) {
        if (self.onUninstallFailed != nil) self.onUninstallFailed();
        [self showError:error];
        return;
    }
    BOOL removeSettings = clearSettings.state == NSControlStateValueOn;
    [NSWorkspace.sharedWorkspace recycleURLs:@[bundleURL]
        completionHandler:^(NSDictionary<NSURL *,NSURL *> *destinations, NSError *recycleError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (recycleError != nil || destinations[bundleURL] == nil) {
                if (self.onUninstallFailed != nil) self.onUninstallFailed();
                [self showError:recycleError != nil ? recycleError : MLLifecycleError(MLLL(@"Please move MicLock to the Trash in Finder."))];
                return;
            }
            NSMutableArray<NSString *> *failures = [NSMutableArray array];
            if (removeSettings) {
                // Test overrides and legacy directories are intentionally not
                // consulted. Only this modern product's exact state is removed.
                NSURL *base = [NSFileManager.defaultManager URLForDirectory:NSApplicationSupportDirectory
                    inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
                NSURL *directory = [base URLByAppendingPathComponent:@"MicLock" isDirectory:YES];
                NSError *listError = nil;
                NSArray<NSURL *> *files = MLUninstallStateFilesAtURL(directory, &listError);
                if (listError != nil) [failures addObject:listError.localizedDescription];
                for (NSURL *file in files) {
                    // unlink cannot recursively remove a directory if another
                    // process replaces a reviewed file between list and cleanup.
                    if (unlink(file.fileSystemRepresentation) != 0) {
                        NSError *removeError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
                        [failures addObject:removeError.localizedDescription];
                    }
                }
                NSArray *remaining = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory
                    includingPropertiesForKeys:nil options:0 error:nil];
                if (remaining.count == 0) rmdir(directory.fileSystemRepresentation);
                else [failures addObject:MLLL(@"Other files in the MicLock settings folder were preserved.")];
                [NSUserDefaults.standardUserDefaults removePersistentDomainForName:@"io.github.liuzhengyi.miclock"];
            }
            if (failures.count > 0) {
                NSAlert *done = [[NSAlert alloc] init];
                done.messageText = MLLL(@"MicLock was moved to the Trash");
                done.informativeText = [failures componentsJoinedByString:@"\n"];
                [done addButtonWithTitle:MLLL(@"OK")];
                [done runModal];
            }
            [NSApp terminate:nil];
        });
    }];
}
@end
