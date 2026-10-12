#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, MLAudioDeviceKind) {
    MLAudioDeviceKindBuiltIn,
    MLAudioDeviceKindBluetooth,
    MLAudioDeviceKindExternal,
    MLAudioDeviceKindVirtual,
    MLAudioDeviceKindUnknown,
};

@interface MLAudioDevice : NSObject
@property(nonatomic) AudioDeviceID deviceID;
@property(nonatomic, copy) NSString *uid;
@property(nonatomic, copy) NSString *name;
@property(nonatomic) UInt32 transportType;
@property(nonatomic) BOOL alive;
@property(nonatomic, readonly) MLAudioDeviceKind kind;
@property(nonatomic, readonly) NSString *transportLabel;
@end

FOUNDATION_EXPORT NSArray<MLAudioDevice *> *MLAudioInputDevices(NSError **error);
FOUNDATION_EXPORT MLAudioDevice * _Nullable MLAudioCurrentInput(NSError **error);
FOUNDATION_EXPORT MLAudioDevice * _Nullable MLAudioDeviceForUID(NSString *uid, NSError **error);
FOUNDATION_EXPORT MLAudioDevice * _Nullable MLAudioUniqueBuiltInFromDevices(
    NSArray<MLAudioDevice *> *devices);
FOUNDATION_EXPORT MLAudioDevice * _Nullable MLAudioUniqueBuiltInInput(NSError **error);
FOUNDATION_EXPORT BOOL MLAudioSetDefaultInputUID(NSString *uid, NSError **error);
FOUNDATION_EXPORT NSError *MLAudioError(OSStatus status, NSString *operation);

NS_ASSUME_NONNULL_END
