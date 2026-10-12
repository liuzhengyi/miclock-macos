#import <AppKit/AppKit.h>
#import "MLStatusBadgeView.h"
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        [NSApplication sharedApplication];
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:720 pixelsHigh:160 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = context;
        [[NSColor colorWithWhite:0.15 alpha:1] setFill];
        NSRectFill(NSMakeRect(0,0,720,160));
        NSArray *letters = @[@"M", @"B", @"E", @"V", @"O", @"!"];
        for (NSUInteger i=0; i<letters.count; i++) {
            CGContextSaveGState(context.CGContext);
            CGContextTranslateCTM(context.CGContext, 20+i*120, 50);
            CGContextScaleCTM(context.CGContext, 8, 8);
            MLStatusBadgeView *view = [[MLStatusBadgeView alloc] initWithFrame:NSMakeRect(0,0,9.5,9.5)];
            view.badgeText = letters[i];
            view.badgeColor = i==5 ? NSColor.systemRedColor : NSColor.systemBlueColor;
            [view drawRect:view.bounds];
            CGContextRestoreGState(context.CGContext);
            [letters[i] drawAtPoint:NSMakePoint(50+i*120,15) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:16],NSForegroundColorAttributeName:NSColor.whiteColor}];
        }
        [NSGraphicsContext restoreGraphicsState];
        NSData *data=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        return [data writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES] ? 0 : 1;
    }
}
