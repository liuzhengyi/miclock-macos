#pragma once

#import <Foundation/Foundation.h>
#import <math.h>

// AppKit does not expose a public status-item positioning API. The preferred-
// position key below is an AppKit storage convention, not a documented API.
// Keep this compatibility repair isolated to MicLock's own autosave name.
// It never reads or writes Control Center's private database or other items.
// Passing the pure checks does not establish that a glyph is visible on screen.
static inline BOOL MLStatusPlacementNeedsReset(id _Nullable preferredPosition, CGFloat availableWidth) {
    if (![preferredPosition isKindOfClass:NSNumber.class]) return YES;
    double position = [preferredPosition doubleValue];
    if (!isfinite(position) || position < 0) return YES;
    // Without a useful display measurement, preserve a valid saved position.
    // The 38-point allowance covers the current status-item host plus margins.
    if (!isfinite(availableWidth) || availableWidth <= 38.0) return NO;
    return position > availableWidth - 38.0;
}

static inline BOOL MLStatusPlacementPrepareDefaults(NSUserDefaults * _Nullable defaults,
                                                     NSString * _Nullable autosaveName,
                                                     CGFloat availableWidth) {
    if (defaults == nil || autosaveName.length == 0) return NO;
    NSString *key = [@"NSStatusItem Preferred Position " stringByAppendingString:autosaveName];
    if (!MLStatusPlacementNeedsReset([defaults objectForKey:key], availableWidth)) return NO;
    [defaults setObject:@0 forKey:key];
    return YES;
}
