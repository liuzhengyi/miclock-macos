#import <AppKit/AppKit.h>

static NSUInteger Ink(NSBitmapImageRep *bitmap, NSInteger x0, NSInteger y0, NSInteger x1, NSInteger y1) {
    NSUInteger count = 0;
    for (NSInteger y = y0; y < y1; y += 2) for (NSInteger x = x0; x < x1; x += 2) {
        NSColor *color = [[bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
        if (color != nil && color.alphaComponent > 0.9 && color.redComponent < 0.65 &&
            color.greenComponent < 0.65 && color.blueComponent < 0.65) count++;
    }
    return count;
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        NSBitmapImageRep *bitmap = data != nil ? [NSBitmapImageRep imageRepWithData:data] : nil;
        // These spatial checks caught the real 2x+2x scaling defect: the top
        // title disappeared and the central arrow was outside the canvas.
        BOOL pass = bitmap != nil && bitmap.pixelsWide == 1280 && bitmap.pixelsHigh == 800 &&
            fabs(bitmap.size.width - 640) < 1 && fabs(bitmap.size.height - 400) < 1 &&
            Ink(bitmap,100,40,1050,240) > 200 && Ink(bitmap,530,360,740,460) > 40 &&
            Ink(bitmap,100,590,1200,750) > 200;
        if (!pass) { fprintf(stderr,"FAIL: DMG Retina canvas must contain top instructions, central arrow and footer.\n"); return 1; }
        printf("DMG background spatial regression passed; actual Finder rendering remains a separate acceptance check.\n");
    }
    return 0;
}
