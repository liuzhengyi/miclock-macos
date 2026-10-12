#import <Foundation/Foundation.h>
#import "MLLifecycle.h"
#import "MLUpdate.h"

static NSUInteger Count;
static void Assert(BOOL condition, NSString *message) {
    Count++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
int main(void) {
    @autoreleasepool {
        NSString *root = NSProcessInfo.processInfo.environment[@"MICLOCK_LIFECYCLE_TEST_DIR"];
        Assert(root.isAbsolutePath && [root containsString:@"miclock-tests."], @"isolated temporary directory required");
        NSURL *base = [NSURL fileURLWithPath:root isDirectory:YES].URLByResolvingSymlinksInPath;
        NSURL *home = [base URLByAppendingPathComponent:@"test-home" isDirectory:YES];
        NSURL *apps = [home URLByAppendingPathComponent:@"Applications" isDirectory:YES];
        Assert([NSFileManager.defaultManager createDirectoryAtURL:apps withIntermediateDirectories:YES attributes:nil error:nil], @"test Applications created");
        Assert(MLUninstallPathIsAllowed([apps URLByAppendingPathComponent:@"MicLock.app"], home), @"own app under user Applications allowed");
        for (NSString *relative in @[@"MicLock.app", @"Downloads/MicLock.app", @"Applications/Other.app",
            @"Applications/MicLock.app/Contents", @"Applications/Nested/MicLock.app", @"Applications/../Downloads/MicLock.app"]) {
            Assert(!MLUninstallPathIsAllowed([home URLByAppendingPathComponent:relative], home), @"noninstallation path rejected");
        }
        Assert(!MLUninstallPathIsAllowed([NSURL URLWithString:@"https://example.com/MicLock.app"], home), @"nonfile URL rejected");
        NSURL *link = [apps URLByAppendingPathComponent:@"MicLock.app"];
        Assert([NSFileManager.defaultManager createSymbolicLinkAtPath:link.path withDestinationPath:@"/Applications/Other.app" error:nil], @"test symlink created");
        Assert(!MLUninstallPathIsAllowed(link, home), @"app symlink rejected");
        [NSFileManager.defaultManager removeItemAtURL:link error:nil];

        NSURL *state = [base URLByAppendingPathComponent:@"state" isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:state withIntermediateDirectories:YES attributes:nil error:nil];
        for (NSString *name in MLUninstallKnownStateFiles()) {
            [@"test" writeToURL:[state URLByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        NSURL *unknown = [state URLByAppendingPathComponent:@"user-note.txt"];
        [@"preserve" writeToURL:unknown atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSError *error = nil;
        NSArray<NSURL *> *safe = MLUninstallStateFilesAtURL(state, &error);
        Assert(safe.count == 6 && error == nil, @"only six known regular files selected");
        Assert(![safe containsObject:unknown], @"unknown user file excluded");
        NSURL *draft = [state URLByAppendingPathComponent:@"feedback-draft.json"];
        [NSFileManager.defaultManager removeItemAtURL:draft error:nil];
        [NSFileManager.defaultManager createSymbolicLinkAtPath:draft.path withDestinationPath:unknown.path error:nil];
        error = nil;
        safe = MLUninstallStateFilesAtURL(state, &error);
        Assert(safe.count == 5 && error != nil && ![safe containsObject:draft], @"state symlink preserved with warning");
        [NSFileManager.defaultManager removeItemAtURL:draft error:nil];
        [NSFileManager.defaultManager createDirectoryAtURL:draft withIntermediateDirectories:NO attributes:nil error:nil];
        error = nil;
        Assert(MLUninstallStateFilesAtURL(state, &error).count == 5 && error != nil, @"directory with known filename preserved");
        NSURL *stateLink = [base URLByAppendingPathComponent:@"state-link"];
        [NSFileManager.defaultManager createSymbolicLinkAtPath:stateLink.path withDestinationPath:state.path error:nil];
        error = nil;
        Assert(MLUninstallStateFilesAtURL(stateLink, &error).count == 0 && error != nil, @"linked state directory rejected");
        Assert([[NSString stringWithContentsOfURL:unknown encoding:NSUTF8StringEncoding error:nil] isEqualToString:@"preserve"], @"all tests leave unknown content unchanged");

        NSString *prefix = @"https://ecnkfnba0c1r.feishuapp.com/app/app_17ftjhzb3vs/downloads/";
        Assert(MLUpdateDownloadURLIsAllowed([NSURL URLWithString:[prefix stringByAppendingString:@"MicLock-3.2.0.dmg"]]), @"canonical DMG update URL allowed");
        Assert(MLUpdateDownloadURLIsAllowed([NSURL URLWithString:[prefix stringByAppendingString:@"MicLock-3.2.1.zip"]]), @"canonical ZIP update URL allowed");
        for (NSString *url in @[
            @"http://ecnkfnba0c1r.feishuapp.com/app/app_17ftjhzb3vs/downloads/MicLock-3.2.0.dmg",
            @"https://example.com/app/app_17ftjhzb3vs/downloads/MicLock-3.2.0.dmg",
            @"https://ecnkfnba0c1r.feishuapp.com/app/other/downloads/MicLock-3.2.0.dmg",
            @"https://ecnkfnba0c1r.feishuapp.com/app/app_17ftjhzb3vs/downloads/Other-3.2.0.dmg",
            @"https://ecnkfnba0c1r.feishuapp.com/app/app_17ftjhzb3vs/downloads/MicLock-3.2.0.pkg",
            @"https://ecnkfnba0c1r.feishuapp.com/app/app_17ftjhzb3vs/downloads/MicLock-3.2.0.dmg?target=other",
            @"https://ecnkfnba0c1r.feishuapp.com/app/app_17ftjhzb3vs/downloads/MicLock-3.2.0.dmg#other",
            @"https://user:password@ecnkfnba0c1r.feishuapp.com/app/app_17ftjhzb3vs/downloads/MicLock-3.2.0.dmg",
            @"https://ecnkfnba0c1r.feishuapp.com:9443/app/app_17ftjhzb3vs/downloads/MicLock-3.2.0.dmg",
            @"https://ecnkfnba0c1r.feishuapp.com/app/app_17ftjhzb3vs/downloads/%2e%2e/MicLock-3.2.0.dmg",
            @"https://ecnkfnba0c1r.feishuapp.com/app/app_17ftjhzb3vs/downloads/MicLock-3.2.0.dmg/../../Other.app"
        ]) Assert(!MLUpdateDownloadURLIsAllowed([NSURL URLWithString:url]), @"unsafe update URL rejected");
        printf("Lifecycle/update policy tests passed (%lu assertions); no app, login item or user data changed.\n", (unsigned long)Count);
    }
    return 0;
}
