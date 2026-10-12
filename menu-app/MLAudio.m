#import "MLAudio.h"
#import <AudioToolbox/AudioToolbox.h>

static NSString * const MLAudioErrorDomain = @"io.github.liuzhengyi.miclock.audio";

NSError *MLAudioError(OSStatus status, NSString *operation) {
    UInt32 value = CFSwapInt32HostToBig((UInt32)status);
    char text[5] = {0};
    memcpy(text, &value, 4);
    BOOL printable = YES;
    for (NSUInteger index = 0; index < 4; index++) {
        if (text[index] < 32 || text[index] > 126) printable = NO;
    }
    NSString *detail = printable
        ? [NSString stringWithFormat:@"'%s'", text]
        : [NSString stringWithFormat:@"%d", (int)status];
    return [NSError errorWithDomain:MLAudioErrorDomain
                               code:status
                           userInfo:@{NSLocalizedDescriptionKey:
        [NSString stringWithFormat:@"%@ failed (%@)", operation, detail]}];
}

@implementation MLAudioDevice

- (MLAudioDeviceKind)kind {
    switch (self.transportType) {
        case kAudioDeviceTransportTypeBuiltIn:
            return MLAudioDeviceKindBuiltIn;
        case kAudioDeviceTransportTypeBluetooth:
        case kAudioDeviceTransportTypeBluetoothLE:
            return MLAudioDeviceKindBluetooth;
        case kAudioDeviceTransportTypeUSB:
        case kAudioDeviceTransportTypePCI:
        case kAudioDeviceTransportTypeFireWire:
        case kAudioDeviceTransportTypeThunderbolt:
        case kAudioDeviceTransportTypeDisplayPort:
        case kAudioDeviceTransportTypeHDMI:
            return MLAudioDeviceKindExternal;
        case kAudioDeviceTransportTypeVirtual:
        case kAudioDeviceTransportTypeAggregate:
            return MLAudioDeviceKindVirtual;
        default:
            return MLAudioDeviceKindUnknown;
    }
}

- (NSString *)transportLabel {
    switch (self.kind) {
        case MLAudioDeviceKindBuiltIn: return @"Built-in";
        case MLAudioDeviceKindBluetooth: return @"Bluetooth";
        case MLAudioDeviceKindExternal: return @"External";
        case MLAudioDeviceKindVirtual: return @"Virtual";
        case MLAudioDeviceKindUnknown: return @"Other";
    }
}

@end

static BOOL MLDeviceHasInputChannels(AudioDeviceID deviceID) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyStreamConfiguration,
        kAudioDevicePropertyScopeInput,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(deviceID, &address, 0, NULL, &size) != noErr || size == 0) {
        return NO;
    }
    AudioBufferList *buffers = calloc(1, size);
    if (buffers == NULL) return NO;
    OSStatus status = AudioObjectGetPropertyData(deviceID, &address, 0, NULL, &size, buffers);
    UInt32 channels = 0;
    if (status == noErr) {
        for (UInt32 index = 0; index < buffers->mNumberBuffers; index++) {
            channels += buffers->mBuffers[index].mNumberChannels;
        }
    }
    free(buffers);
    return status == noErr && channels > 0;
}

static NSString *MLStringProperty(AudioObjectID objectID,
                                  AudioObjectPropertySelector selector) {
    AudioObjectPropertyAddress address = {
        selector,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    CFStringRef value = NULL;
    UInt32 size = sizeof(value);
    if (AudioObjectGetPropertyData(objectID, &address, 0, NULL, &size, &value) != noErr || value == NULL) {
        return @"";
    }
    return CFBridgingRelease(value);
}

static UInt32 MLUInt32Property(AudioObjectID objectID,
                               AudioObjectPropertySelector selector,
                               UInt32 fallback) {
    AudioObjectPropertyAddress address = {
        selector,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 value = fallback;
    UInt32 size = sizeof(value);
    if (AudioObjectGetPropertyData(objectID, &address, 0, NULL, &size, &value) != noErr) {
        return fallback;
    }
    return value;
}

static MLAudioDevice *MLDeviceFromID(AudioDeviceID deviceID) {
    if (deviceID == kAudioObjectUnknown || !MLDeviceHasInputChannels(deviceID)) return nil;
    NSString *uid = MLStringProperty(deviceID, kAudioDevicePropertyDeviceUID);
    NSString *name = MLStringProperty(deviceID, kAudioObjectPropertyName);
    if (uid.length == 0 || name.length == 0) return nil;

    MLAudioDevice *device = [[MLAudioDevice alloc] init];
    device.deviceID = deviceID;
    device.uid = uid;
    device.name = name;
    device.transportType = MLUInt32Property(deviceID, kAudioDevicePropertyTransportType, 0);
    device.alive = MLUInt32Property(deviceID, kAudioDevicePropertyDeviceIsAlive, 1) != 0;
    return device;
}

NSArray<MLAudioDevice *> *MLAudioInputDevices(NSError **error) {
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,
                                                     &address, 0, NULL, &size);
    if (status != noErr) {
        if (error != NULL) *error = MLAudioError(status, @"Enumerating audio devices");
        return @[];
    }
    NSUInteger count = size / sizeof(AudioDeviceID);
    if (count == 0) return @[];
    AudioDeviceID *ids = calloc(count, sizeof(AudioDeviceID));
    if (ids == NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:MLAudioErrorDomain code:ENOMEM
                                     userInfo:@{NSLocalizedDescriptionKey: @"Out of memory"}];
        }
        return @[];
    }
    status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                        &address, 0, NULL, &size, ids);
    if (status != noErr) {
        free(ids);
        if (error != NULL) *error = MLAudioError(status, @"Reading audio devices");
        return @[];
    }

    NSMutableArray<MLAudioDevice *> *devices = [NSMutableArray array];
    for (NSUInteger index = 0; index < count; index++) {
        MLAudioDevice *device = MLDeviceFromID(ids[index]);
        if (device != nil && device.alive) [devices addObject:device];
    }
    free(ids);
    [devices sortUsingComparator:^NSComparisonResult(MLAudioDevice *left, MLAudioDevice *right) {
        if (left.kind != right.kind) {
            return left.kind < right.kind ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left.name localizedStandardCompare:right.name];
    }];
    return devices;
}

MLAudioDevice *MLAudioCurrentInput(NSError **error) {
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioDeviceID deviceID = kAudioObjectUnknown;
    UInt32 size = sizeof(deviceID);
    OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                                 &address, 0, NULL, &size, &deviceID);
    if (status != noErr) {
        if (error != NULL) *error = MLAudioError(status, @"Reading the default input");
        return nil;
    }
    MLAudioDevice *device = MLDeviceFromID(deviceID);
    if (device == nil && error != NULL) {
        *error = [NSError errorWithDomain:MLAudioErrorDomain code:-1
                                 userInfo:@{NSLocalizedDescriptionKey: @"The default input is unavailable"}];
    }
    return device;
}

MLAudioDevice *MLAudioDeviceForUID(NSString *uid, NSError **error) {
    for (MLAudioDevice *device in MLAudioInputDevices(error)) {
        if ([device.uid isEqualToString:uid]) return device;
    }
    return nil;
}

MLAudioDevice *MLAudioUniqueBuiltInFromDevices(NSArray<MLAudioDevice *> *devices) {
    NSMutableArray<MLAudioDevice *> *builtIns = [NSMutableArray array];
    for (MLAudioDevice *device in devices) {
        if (device.kind == MLAudioDeviceKindBuiltIn) [builtIns addObject:device];
    }
    return builtIns.count == 1 ? builtIns.firstObject : nil;
}

MLAudioDevice *MLAudioUniqueBuiltInInput(NSError **error) {
    return MLAudioUniqueBuiltInFromDevices(MLAudioInputDevices(error));
}

BOOL MLAudioSetDefaultInputUID(NSString *uid, NSError **error) {
    NSError *lookupError = nil;
    MLAudioDevice *device = MLAudioDeviceForUID(uid, &lookupError);
    if (device == nil) {
        if (error != NULL) {
            *error = lookupError != nil ? lookupError
                : [NSError errorWithDomain:MLAudioErrorDomain code:-2
                                  userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Input device is unavailable: %@", uid]}];
        }
        return NO;
    }
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioDeviceID deviceID = device.deviceID;
    UInt32 size = sizeof(deviceID);
    OSStatus status = AudioObjectSetPropertyData(kAudioObjectSystemObject,
                                                 &address, 0, NULL, size, &deviceID);
    if (status != noErr) {
        if (error != NULL) *error = MLAudioError(status, @"Changing the default input");
        return NO;
    }
    return YES;
}
