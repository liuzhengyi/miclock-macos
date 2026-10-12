#import "MLState.h"
#import "MLAudio.h"
#import <CommonCrypto/CommonDigest.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

NSString * const MLConfigChangedNotification = @"io.github.liuzhengyi.miclock.config-changed";
NSString * const MLTerminateNotification = @"io.github.liuzhengyi.miclock.terminate";
NSString * const MLConfigEnabledKey = @"enabled";
NSString * const MLConfigTargetUIDKey = @"targetUID";
NSString * const MLConfigTargetNameKey = @"targetName";

static const NSInteger MLConfigurationVersion = 3;

NSURL *MLSupportDirectoryURL(void) {
    NSString *override = NSProcessInfo.processInfo.environment[@"MICLOCK_SUPPORT_DIR"];
    if (override.length > 0 && override.isAbsolutePath) {
        return [NSURL fileURLWithPath:override isDirectory:YES];
    }
    NSURL *base = [NSFileManager.defaultManager URLForDirectory:NSApplicationSupportDirectory
                                                       inDomain:NSUserDomainMask
                                              appropriateForURL:nil
                                                         create:NO
                                                          error:nil];
    return [base URLByAppendingPathComponent:@"MicLock" isDirectory:YES];
}

NSURL *MLConfigurationURL(void) {
    return [MLSupportDirectoryURL() URLByAppendingPathComponent:@"config.plist"];
}

NSURL *MLHealthURL(void) {
    return [MLSupportDirectoryURL() URLByAppendingPathComponent:@"health.plist"];
}

static BOOL MLEnsureSupportDirectory(NSError **error) {
    BOOL created = [NSFileManager.defaultManager createDirectoryAtURL:MLSupportDirectoryURL()
                                          withIntermediateDirectories:YES
                                                           attributes:@{NSFilePosixPermissions: @0700}
                                                                error:error];
    if (created) {
        [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0700}
                                       ofItemAtPath:MLSupportDirectoryURL().path
                                              error:nil];
    }
    return created;
}

static BOOL MLWriteDictionaryUnlocked(NSDictionary *dictionary, NSURL *url, NSError **error) {
    if (!MLEnsureSupportDirectory(error)) return NO;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:dictionary
                                                               format:NSPropertyListBinaryFormat_v1_0
                                                              options:0
                                                                error:error];
    if (data == nil) return NO;

    BOOL success = [data writeToURL:url options:NSDataWritingAtomic error:error];
    if (success) chmod(url.fileSystemRepresentation, 0600);
    return success;
}

static BOOL MLWithStateLock(NSString *name, BOOL (^action)(NSError **), NSError **error) {
    if (!MLEnsureSupportDirectory(error)) return NO;
    NSString *lockPath = [MLSupportDirectoryURL().path stringByAppendingPathComponent:name];
    int descriptor = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR | O_CLOEXEC, 0600);
    if (descriptor < 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        }
        return NO;
    }
    if (flock(descriptor, LOCK_EX) != 0) {
        int savedErrno = errno;
        close(descriptor);
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil];
        }
        return NO;
    }
    BOOL success = action(error);
    flock(descriptor, LOCK_UN);
    close(descriptor);
    return success;
}

static NSDictionary *MLReadDictionary(NSURL *url) {
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:nil];
    if (data == nil) return @{};
    id value = [NSPropertyListSerialization propertyListWithData:data
                                                         options:NSPropertyListImmutable
                                                          format:nil
                                                           error:nil];
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static NSDictionary *MLMigratedLegacyConfiguration(void) {
    // Test overrides must not inspect or migrate the real user's legacy state.
    if (NSProcessInfo.processInfo.environment[@"MICLOCK_SUPPORT_DIR"].length > 0) return @{};
    NSString *legacyPath = [NSHomeDirectory() stringByAppendingPathComponent:@".config/mic-input-lock/device-name"];
    NSString *legacyName = [NSString stringWithContentsOfFile:legacyPath
                                                     encoding:NSUTF8StringEncoding
                                                        error:nil];
    legacyName = [legacyName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSArray<MLAudioDevice *> *devices = MLAudioInputDevices(NULL);
    MLAudioDevice *target = nil;
    if (legacyName.length > 0) {
        NSMutableArray<MLAudioDevice *> *matches = [NSMutableArray array];
        for (MLAudioDevice *device in devices) {
            if ([device.name isEqualToString:legacyName]) [matches addObject:device];
        }
        if (matches.count == 1) target = matches.firstObject;
    }
    if (target == nil) return @{};
    return @{
        @"configurationVersion": @(MLConfigurationVersion),
        MLConfigEnabledKey: @YES,
        MLConfigTargetUIDKey: target.uid,
        MLConfigTargetNameKey: target.name,
    };
}

static NSDictionary *MLValidatedConfiguration(NSDictionary *configuration) {
    NSMutableDictionary *value = [configuration mutableCopy];
    if (![value[MLConfigTargetUIDKey] isKindOfClass:NSString.class] ||
        [value[MLConfigTargetUIDKey] length] == 0) {
        [value removeObjectForKey:MLConfigTargetUIDKey];
        [value removeObjectForKey:MLConfigTargetNameKey];
    }
    if (![value[MLConfigTargetNameKey] isKindOfClass:NSString.class]) {
        [value removeObjectForKey:MLConfigTargetNameKey];
    }
    BOOL enabled = [value[MLConfigEnabledKey] isKindOfClass:NSNumber.class] &&
        [value[MLConfigEnabledKey] boolValue] && value[MLConfigTargetUIDKey] != nil;
    value[MLConfigEnabledKey] = @(enabled);
    value[@"configurationVersion"] = @(MLConfigurationVersion);
    return value;
}

NSDictionary *MLLoadConfiguration(void) {
    return MLValidatedConfiguration(MLReadDictionary(MLConfigurationURL()));
}

BOOL MLWithLockedConfiguration(BOOL (^action)(NSDictionary *, NSError **), NSError **error) {
    return MLWithStateLock(@"config.lock", ^BOOL(NSError **innerError) {
        return action(MLLoadConfiguration(), innerError);
    }, error);
}

BOOL MLInitializeConfiguration(NSError **error) {
    return MLWithLockedConfiguration(^BOOL(NSDictionary *configuration, NSError **innerError) {
        if ([configuration[MLConfigTargetUIDKey] length] > 0) return YES;
        NSDictionary *migrated = MLMigratedLegacyConfiguration();
        NSMutableDictionary *value = [configuration mutableCopy];
        if (migrated.count > 0) {
            [value addEntriesFromDictionary:migrated];
        } else {
            MLAudioDevice *builtIn = MLAudioUniqueBuiltInInput(NULL);
            if (builtIn != nil) {
                value[MLConfigTargetUIDKey] = builtIn.uid;
                value[MLConfigTargetNameKey] = builtIn.name;
            }
            value[MLConfigEnabledKey] = @NO;
        }
        value[@"updatedAt"] = NSDate.date;
        return MLWriteDictionaryUnlocked(MLValidatedConfiguration(value),
                                         MLConfigurationURL(), innerError);
    }, error);
}

BOOL MLSaveConfiguration(NSDictionary *configuration, NSError **error) {
    NSMutableDictionary *value = [MLValidatedConfiguration(configuration) mutableCopy];
    value[@"configurationVersion"] = @(MLConfigurationVersion);
    value[@"updatedAt"] = NSDate.date;
    return MLWithStateLock(@"config.lock", ^BOOL(NSError **innerError) {
        return MLWriteDictionaryUnlocked(value, MLConfigurationURL(), innerError);
    }, error);
}

BOOL MLUpdateConfiguration(NSDictionary *changes, NSError **error) {
    return MLWithLockedConfiguration(^BOOL(NSDictionary *configuration, NSError **innerError) {
        NSMutableDictionary *value = [configuration mutableCopy];
        [value addEntriesFromDictionary:changes];
        value[@"updatedAt"] = NSDate.date;
        return MLWriteDictionaryUnlocked(MLValidatedConfiguration(value),
                                         MLConfigurationURL(), innerError);
    }, error);
}

BOOL MLSetConfigurationEnabled(BOOL enabled, NSError **error) {
    return MLWithLockedConfiguration(^BOOL(NSDictionary *configuration, NSError **innerError) {
        NSMutableDictionary *value = [configuration mutableCopy];
        if (enabled && [value[MLConfigTargetUIDKey] length] == 0) {
            MLAudioDevice *builtIn = MLAudioUniqueBuiltInInput(NULL);
            if (builtIn == nil) {
                if (innerError != NULL) {
                    *innerError = [NSError errorWithDomain:@"io.github.liuzhengyi.miclock.state"
                        code:1 userInfo:@{NSLocalizedDescriptionKey:
                            NSLocalizedString(@"Choose a lock target first.", nil)}];
                }
                return NO;
            }
            value[MLConfigTargetUIDKey] = builtIn.uid;
            value[MLConfigTargetNameKey] = builtIn.name;
        }
        value[MLConfigEnabledKey] = @(enabled);
        value[@"updatedAt"] = NSDate.date;
        return MLWriteDictionaryUnlocked(MLValidatedConfiguration(value),
                                         MLConfigurationURL(), innerError);
    }, error);
}

NSDictionary *MLLoadHealth(void) {
    return MLReadDictionary(MLHealthURL());
}

BOOL MLSaveHealth(NSDictionary *health, NSError **error) {
    NSMutableDictionary *value = [health mutableCopy];
    value[@"updatedAt"] = NSDate.date;
    return MLWithStateLock(@"health.lock", ^BOOL(NSError **innerError) {
        return MLWriteDictionaryUnlocked(value, MLHealthURL(), innerError);
    }, error);
}

void MLPostConfigurationChanged(void) {
    [NSDistributedNotificationCenter.defaultCenter
        postNotificationName:MLConfigChangedNotification object:nil userInfo:nil deliverImmediately:YES];
}

void MLPostTerminate(void) {
    [NSDistributedNotificationCenter.defaultCenter
        postNotificationName:MLTerminateNotification object:nil userInfo:nil deliverImmediately:YES];
}

NSString *MLRedactedIdentifier(NSString *value) {
    if (value.length == 0) return @"<none>";
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *shortHash = [NSMutableString string];
    for (NSUInteger index = 0; index < 6; index++) {
        [shortHash appendFormat:@"%02x", digest[index]];
    }
    return [NSString stringWithFormat:@"device-%@", shortHash];
}
