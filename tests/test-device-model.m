#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#import "MLAudio.h"

static MLAudioDevice *Device(NSString *uid, NSString *name, UInt32 transport) {
    MLAudioDevice *device = [[MLAudioDevice alloc] init];
    device.uid = uid;
    device.name = name;
    device.transportType = transport;
    device.alive = YES;
    return device;
}

static void Assert(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        MLAudioDevice *builtIn = Device(@"builtin", @"MacBook Air-Mikrofon",
                                        kAudioDeviceTransportTypeBuiltIn);
        MLAudioDevice *bluetooth = Device(@"bluetooth", @"MacBook Microphone",
                                          kAudioDeviceTransportTypeBluetooth);
        Assert(builtIn.kind == MLAudioDeviceKindBuiltIn,
               @"built-in detection must use transport, not localized name");
        Assert(bluetooth.kind == MLAudioDeviceKindBluetooth,
               @"Bluetooth detection must ignore a misleading display name");
        Assert(MLAudioUniqueBuiltInFromDevices(@[bluetooth, builtIn]) == builtIn,
               @"one built-in device should be selected regardless of locale");
        Assert(MLAudioUniqueBuiltInFromDevices(@[builtIn,
            Device(@"builtin-2", @"Internal Mic", kAudioDeviceTransportTypeBuiltIn)]) == nil,
               @"ambiguous built-in devices must fail closed");
        Assert(MLAudioUniqueBuiltInFromDevices(@[bluetooth]) == nil,
               @"the current or first device must never be used as a fallback");
    }
    return 0;
}
