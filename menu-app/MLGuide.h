#import <Foundation/Foundation.h>

FOUNDATION_EXPORT void MLShowUsageGuide(BOOL recordCompletion);
// Show the same native guide without initializing configuration, starting lock
// enforcement, registering login items, or modifying audio devices.
FOUNDATION_EXPORT int MLRunStandaloneGuide(void);
