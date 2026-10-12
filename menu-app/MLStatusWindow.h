#import <AppKit/AppKit.h>
#import "MLAudio.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLStatusWindowController : NSWindowController
@property(nonatomic, copy, nullable) void (^onToggleAutomaticLock)(void);
@property(nonatomic, copy, nullable) void (^onSelectTarget)(NSString *uid);
@property(nonatomic, copy, nullable) void (^onQuickStart)(void);
@property(nonatomic, copy, nullable) void (^onVoiceInputRecommendations)(void);
@property(nonatomic, copy, nullable) void (^onCopyDiagnostics)(void);
@property(nonatomic, copy, nullable) void (^onReportIssue)(void);
@property(nonatomic, copy, nullable) void (^onCheckForUpdates)(void);
@property(nonatomic, copy, nullable) void (^onVersionHistory)(void);
@property(nonatomic, copy, nullable) void (^onUninstall)(void);
@property(nonatomic, copy, nullable) void (^onAnalyticsConsentChanged)(BOOL enabled);

- (void)updateWithCurrentInput:(nullable MLAudioDevice *)current
                configuration:(NSDictionary *)configuration
                       health:(NSDictionary *)health
            healthDisplayName:(NSString *)healthDisplayName
                      devices:(NSArray<MLAudioDevice *> *)devices;
@end

NS_ASSUME_NONNULL_END
