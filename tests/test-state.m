#import <Foundation/Foundation.h>
#import "MLState.h"
#import <sys/stat.h>

static void Assert(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        NSString *override = NSProcessInfo.processInfo.environment[@"MICLOCK_SUPPORT_DIR"];
        Assert(override.isAbsolutePath && [override containsString:@"miclock-tests."],
               @"test requires a dedicated temporary state directory");
        Assert(![NSFileManager.defaultManager fileExistsAtPath:MLSupportDirectoryURL().path],
               @"start with missing temporary state directory");
        NSDictionary *initial = MLLoadConfiguration();
        Assert(![initial[MLConfigEnabledKey] boolValue], @"missing configuration stays disabled");
        Assert(![NSFileManager.defaultManager fileExistsAtPath:MLSupportDirectoryURL().path],
               @"reading configuration has no write or migration side effects");
        Assert(MLSaveConfiguration(@{MLConfigTargetUIDKey:@"test-device", MLConfigTargetNameKey:@"Test",
                                    MLConfigEnabledKey:@NO}, NULL), @"write isolated initial state");

        dispatch_group_t group = dispatch_group_create();
        for (NSUInteger index = 0; index < 32; index++) {
            dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                @autoreleasepool {
                    NSString *key = [NSString stringWithFormat:@"test-%lu", (unsigned long)index];
                    Assert(MLUpdateConfiguration(@{key:@(index)}, NULL), @"concurrent update succeeds");
                }
            });
        }
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        NSDictionary *merged = MLLoadConfiguration();
        for (NSUInteger index = 0; index < 32; index++) {
            NSString *key = [NSString stringWithFormat:@"test-%lu", (unsigned long)index];
            Assert([merged[key] unsignedIntegerValue] == index && merged[key] != nil,
                   @"concurrent read-modify-write must preserve every independent update");
        }

        dispatch_semaphore_t locked = dispatch_semaphore_create(0);
        dispatch_semaphore_t release = dispatch_semaphore_create(0);
        dispatch_semaphore_t actionDone = dispatch_semaphore_create(0);
        dispatch_semaphore_t pauseDone = dispatch_semaphore_create(0);
        Assert(MLSetConfigurationEnabled(YES, NULL), @"enable isolated target");
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            Assert(MLWithLockedConfiguration(^BOOL(NSDictionary *configuration, NSError **error) {
                (void)error;
                Assert([configuration[MLConfigEnabledKey] boolValue], @"decision observes enabled state");
                dispatch_semaphore_signal(locked);
                dispatch_semaphore_wait(release, DISPATCH_TIME_FOREVER);
                return YES;
            }, NULL), @"routing decision transaction succeeds");
            dispatch_semaphore_signal(actionDone);
        });
        dispatch_semaphore_wait(locked, DISPATCH_TIME_FOREVER);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            Assert(MLSetConfigurationEnabled(NO, NULL), @"pause waits for in-flight routing decision");
            dispatch_semaphore_signal(pauseDone);
        });
        Assert(dispatch_semaphore_wait(pauseDone, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC)) != 0,
               @"pause cannot be confirmed before an in-flight routing write completes");
        dispatch_semaphore_signal(release);
        dispatch_semaphore_wait(actionDone, DISPATCH_TIME_FOREVER);
        dispatch_semaphore_wait(pauseDone, DISPATCH_TIME_FOREVER);
        Assert(![MLLoadConfiguration()[MLConfigEnabledKey] boolValue], @"completed pause remains disabled");

        Assert(MLWithLockedConfiguration(^BOOL(NSDictionary *configuration, NSError **error) {
            (void)configuration;
            return MLSaveHealth(@{@"status":@"disabled"}, error);
        }, NULL), @"health uses a separate lock and does not deadlock inside a routing transaction");
        Assert(MLSaveConfiguration(@{MLConfigTargetUIDKey:@123, MLConfigTargetNameKey:@[],
                                    MLConfigEnabledKey:@{}}, NULL), @"malformed known fields are sanitized");
        NSDictionary *sanitized = MLLoadConfiguration();
        Assert(sanitized[MLConfigTargetUIDKey] == nil, @"wrong typed UID is removed");
        Assert(sanitized[MLConfigTargetNameKey] == nil, @"wrong typed name is removed");
        Assert(![sanitized[MLConfigEnabledKey] boolValue], @"malformed enabled value fails closed");
        struct stat info;
        Assert(stat(MLConfigurationURL().fileSystemRepresentation, &info) == 0 && (info.st_mode & 0777) == 0600,
               @"configuration permissions remain private");
        printf("Isolated state tests passed.\n");
    }
    return 0;
}
