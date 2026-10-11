#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#import <math.h>

@interface MLStatusBadgeView : NSView
@property(nonatomic, strong) NSColor *badgeColor;
@property(nonatomic, copy) NSString *badgeText;
@end

@implementation MLStatusBadgeView
- (BOOL)isOpaque { return NO; }
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
- (BOOL)isAccessibilityElement { return NO; }
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSGraphicsContext.currentContext.shouldAntialias = YES;
    BOOL contrast = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldIncreaseContrast;
    NSRect circle = NSInsetRect(self.bounds, 0.2, 0.2);
    [(self.badgeColor != nil ? self.badgeColor : NSColor.systemRedColor) setFill];
    [[NSBezierPath bezierPathWithOvalInRect:circle] fill];
    [(contrast ? NSColor.labelColor : [NSColor.whiteColor colorWithAlphaComponent:0.95]) setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(circle, 0.35, 0.35)];
    border.lineWidth = contrast ? 1.2 : 0.8;
    [border stroke];

    // Center the actual glyph ink, excluding font ascender/descender whitespace.
    NSFont *font = [NSFont systemFontOfSize:6.7 weight:NSFontWeightBold];
    CTFontRef ctFont = CTFontCreateWithName((__bridge CFStringRef)font.fontName, font.pointSize, NULL);
    NSString *text = self.badgeText.length ? self.badgeText : @"!";
    UniChar character = [text characterAtIndex:0];
    CGGlyph glyph = 0;
    if (CTFontGetGlyphsForCharacters(ctFont, &character, &glyph, 1)) {
        CGPathRef path = CTFontCreatePathForGlyph(ctFont, glyph, NULL);
        if (path != NULL) {
            CGRect ink = CGPathGetPathBoundingBox(path);
            CGFloat limit = contrast ? 4.6 : 5.3;
            CGFloat scale = fmin(1.0, limit / fmax(ink.size.width, ink.size.height));
            CGContextRef context = NSGraphicsContext.currentContext.CGContext;
            CGContextSaveGState(context);
            CGContextTranslateCTM(context, NSMidX(circle), NSMidY(circle));
            CGContextScaleCTM(context, scale, scale);
            CGContextTranslateCTM(context, -CGRectGetMidX(ink), -CGRectGetMidY(ink));
            CGContextSetFillColorWithColor(context, NSColor.whiteColor.CGColor);
            CGContextAddPath(context, path);
            CGContextFillPath(context);
            CGContextRestoreGState(context);
            CGPathRelease(path);
        }
    }
    CFRelease(ctFont);
}
@end
