#import <AppKit/AppKit.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
            pixelsWide:1280 pixelsHigh:800 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
            isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        bitmap.size = NSMakeSize(640, 400); // Retina pixels with a 640×400 Finder canvas.
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        [[NSColor colorWithWhite:0.98 alpha:1] setFill];
        NSRectFill(NSMakeRect(0, 0, 640, 400));
        NSDictionary *title = @{NSFontAttributeName:[NSFont systemFontOfSize:28 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName:[NSColor colorWithWhite:0.13 alpha:1]};
        NSDictionary *body = @{NSFontAttributeName:[NSFont systemFontOfSize:15],
            NSForegroundColorAttributeName:[NSColor colorWithWhite:0.36 alpha:1]};
        NSDictionary *note = @{NSFontAttributeName:[NSFont systemFontOfSize:12],
            NSForegroundColorAttributeName:[NSColor colorWithWhite:0.45 alpha:1]};
        [@"MicLock · 语音输入伴侣" drawAtPoint:NSMakePoint(52, 324) withAttributes:title];
        [@"将 MicLock 拖入右侧 Applications" drawAtPoint:NSMakePoint(52, 289) withAttributes:body];
        [[NSColor colorWithRed:0.24 green:0.36 blue:0.49 alpha:1] setStroke];
        NSBezierPath *arrow = NSBezierPath.bezierPath;
        arrow.lineWidth = 3; arrow.lineCapStyle = NSLineCapStyleRound; arrow.lineJoinStyle = NSLineJoinStyleRound;
        [arrow moveToPoint:NSMakePoint(272, 192)]; [arrow lineToPoint:NSMakePoint(358, 192)];
        [arrow moveToPoint:NSMakePoint(346, 203)]; [arrow lineToPoint:NSMakePoint(358, 192)];
        [arrow lineToPoint:NSMakePoint(346, 181)]; [arrow stroke];
        [@"然后从“应用程序”打开 MicLock" drawAtPoint:NSMakePoint(52, 66) withAttributes:body];
        [@"Intel 与 Apple 芯片  ·  macOS 13 或更新版本" drawAtPoint:NSMakePoint(52, 39) withAttributes:note];
        [NSGraphicsContext restoreGraphicsState];
        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        return [png writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES] ? 0 : 1;
    }
}
