#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const MLConfigChangedNotification;
FOUNDATION_EXPORT NSString * const MLTerminateNotification;
FOUNDATION_EXPORT NSString * const MLConfigEnabledKey;
FOUNDATION_EXPORT NSString * const MLConfigTargetUIDKey;
FOUNDATION_EXPORT NSString * const MLConfigTargetNameKey;

FOUNDATION_EXPORT NSURL *MLSupportDirectoryURL(void);
FOUNDATION_EXPORT NSURL *MLConfigurationURL(void);
FOUNDATION_EXPORT NSURL *MLHealthURL(void);
FOUNDATION_EXPORT NSDictionary *MLLoadConfiguration(void);
// Reading configuration never creates/migrates files. GUI startup explicitly
// initializes a target, with automatic locking off for a new installation.
FOUNDATION_EXPORT BOOL MLInitializeConfiguration(NSError **error);
FOUNDATION_EXPORT BOOL MLSaveConfiguration(NSDictionary *configuration, NSError **error);
FOUNDATION_EXPORT BOOL MLUpdateConfiguration(NSDictionary *changes, NSError **error);
FOUNDATION_EXPORT BOOL MLSetConfigurationEnabled(BOOL enabled, NSError **error);
// Serialize an enabled/target decision and the resulting CoreAudio write with
// configuration changes from the GUI or CLI. Do not recursively save config
// from this action. Health has its own lock and may be saved here.
FOUNDATION_EXPORT BOOL MLWithLockedConfiguration(
    BOOL (^action)(NSDictionary *configuration, NSError **error), NSError **error);
FOUNDATION_EXPORT NSDictionary *MLLoadHealth(void);
FOUNDATION_EXPORT BOOL MLSaveHealth(NSDictionary *health, NSError **error);
FOUNDATION_EXPORT void MLPostConfigurationChanged(void);
FOUNDATION_EXPORT void MLPostTerminate(void);
FOUNDATION_EXPORT NSString *MLRedactedIdentifier(NSString *value);

NS_ASSUME_NONNULL_END
