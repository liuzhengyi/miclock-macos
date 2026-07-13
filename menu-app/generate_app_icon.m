#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

static void DrawMicrophoneMark(NSRect rect, NSColor *color) {
    CGFloat scale = rect.size.width / 500.0;
    [color setFill];
    [color setStroke];

    // A bold capsule plus a wide yoke stays readable from Finder down to Spotlight.
    NSRect capsuleRect = NSMakeRect(
        rect.origin.x + 166.0 * scale,
        rect.origin.y + 205.0 * scale,
        168.0 * scale,
        250.0 * scale
    );
    [[NSBezierPath bezierPathWithRoundedRect:capsuleRect
                                      xRadius:84.0 * scale
                                      yRadius:84.0 * scale] fill];

    NSBezierPath *yoke = [NSBezierPath bezierPath];
    yoke.lineWidth = 44.0 * scale;
    yoke.lineCapStyle = NSLineCapStyleRound;
    yoke.lineJoinStyle = NSLineJoinStyleRound;
    [yoke moveToPoint:NSMakePoint(rect.origin.x + 100.0 * scale,
                                  rect.origin.y + 310.0 * scale)];
    [yoke curveToPoint:NSMakePoint(rect.origin.x + 250.0 * scale,
                                   rect.origin.y + 92.0 * scale)
          controlPoint1:NSMakePoint(rect.origin.x + 100.0 * scale,
                                    rect.origin.y + 165.0 * scale)
          controlPoint2:NSMakePoint(rect.origin.x + 155.0 * scale,
                                    rect.origin.y + 92.0 * scale)];
    [yoke curveToPoint:NSMakePoint(rect.origin.x + 400.0 * scale,
                                   rect.origin.y + 310.0 * scale)
          controlPoint1:NSMakePoint(rect.origin.x + 345.0 * scale,
                                    rect.origin.y + 92.0 * scale)
          controlPoint2:NSMakePoint(rect.origin.x + 400.0 * scale,
                                    rect.origin.y + 165.0 * scale)];
    [yoke stroke];

    NSBezierPath *stem = [NSBezierPath bezierPath];
    stem.lineWidth = 44.0 * scale;
    stem.lineCapStyle = NSLineCapStyleRound;
    [stem moveToPoint:NSMakePoint(rect.origin.x + 250.0 * scale,
                                  rect.origin.y + 92.0 * scale)];
    [stem lineToPoint:NSMakePoint(rect.origin.x + 250.0 * scale,
                                  rect.origin.y + 38.0 * scale)];
    [stem moveToPoint:NSMakePoint(rect.origin.x + 170.0 * scale,
                                  rect.origin.y + 38.0 * scale)];
    [stem lineToPoint:NSMakePoint(rect.origin.x + 330.0 * scale,
                                  rect.origin.y + 38.0 * scale)];
    [stem stroke];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "usage: generate_app_icon output.png\n");
            return 2;
        }

        [NSApplication sharedApplication];
        const NSInteger size = 1024;
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL
                          pixelsWide:size
                          pixelsHigh:size
                       bitsPerSample:8
                     samplesPerPixel:4
                            hasAlpha:YES
                            isPlanar:NO
                      colorSpaceName:NSCalibratedRGBColorSpace
                         bytesPerRow:0
                        bitsPerPixel:0];
        NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = context;
        context.shouldAntialias = YES;

        [NSColor.clearColor setFill];
        NSRectFill(NSMakeRect(0, 0, size, size));

        NSRect tileRect = NSMakeRect(82, 82, 860, 860);
        NSBezierPath *tile = [NSBezierPath bezierPathWithRoundedRect:tileRect xRadius:215 yRadius:215];
        NSShadow *shadow = [[NSShadow alloc] init];
        shadow.shadowBlurRadius = 34;
        shadow.shadowOffset = NSMakeSize(0, -18);
        shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.30];
        [shadow set];

        NSGradient *gradient = [[NSGradient alloc]
            initWithStartingColor:[NSColor colorWithCalibratedRed:0.31 green:0.27 blue:0.90 alpha:1.0]
                       endingColor:[NSColor colorWithCalibratedRed:0.02 green:0.72 blue:0.78 alpha:1.0]];
        [gradient drawInBezierPath:tile angle:-45.0];

        [NSGraphicsContext restoreGraphicsState];
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = context;
        context.shouldAntialias = YES;

        // Subtle inner highlight makes the icon feel native without changing the mark.
        [[NSColor colorWithWhite:1.0 alpha:0.16] setStroke];
        NSBezierPath *highlight = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(tileRect, 18, 18)
                                                                  xRadius:198
                                                                  yRadius:198];
        highlight.lineWidth = 10;
        [highlight stroke];

        DrawMicrophoneMark(NSMakeRect(258, 262, 500, 500), [NSColor colorWithWhite:1.0 alpha:0.96]);

        // A neutral multi-state badge echoes the live M/A/O/! menu-bar badge.
        NSRect badgeRect = NSMakeRect(675, 150, 215, 215);
        [[NSColor colorWithWhite:0.08 alpha:0.88] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:badgeRect] fill];
        [[NSColor colorWithWhite:1.0 alpha:0.9] setStroke];
        NSBezierPath *badgeBorder = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(badgeRect, 7, 7)];
        badgeBorder.lineWidth = 10;
        [badgeBorder stroke];

        NSArray<NSColor *> *colors = @[
            NSColor.systemBlueColor,
            NSColor.systemTealColor,
            NSColor.systemOrangeColor
        ];
        NSArray<NSValue *> *centers = @[
            [NSValue valueWithPoint:NSMakePoint(728, 258)],
            [NSValue valueWithPoint:NSMakePoint(783, 258)],
            [NSValue valueWithPoint:NSMakePoint(838, 258)]
        ];
        for (NSUInteger i = 0; i < colors.count; i++) {
            [colors[i] setFill];
            NSPoint center = centers[i].pointValue;
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x - 18, center.y - 18, 36, 36)] fill];
        }

        [NSGraphicsContext restoreGraphicsState];
        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        NSString *outputPath = [NSString stringWithUTF8String:argv[1]];
        if (![png writeToFile:outputPath atomically:YES]) {
            fprintf(stderr, "failed to write icon\n");
            return 1;
        }
    }
    return 0;
}
