#import "AppIcon.h"
#import "Theme.h"

// 图标都按 1024 的画布来画，再整体缩放到目标尺寸；坐标原点在左下角

// 鼠标指针：tip 是尖端位置，k 是缩放（原型高 20 个单位、宽 12 个单位）
static NSBezierPath *cursorPath(NSPoint tip, CGFloat k) {
    CGFloat pts[][2] = {{0, 0}, {0, 17}, {4, 13.2}, {6.8, 19.6}, {9.4, 18.5}, {6.7, 12.2}, {12, 12.2}};
    NSBezierPath *p = [NSBezierPath bezierPath];
    for (int i = 0; i < 7; i++) {
        NSPoint q = NSMakePoint(tip.x + pts[i][0] * k, tip.y - pts[i][1] * k);
        i ? [p lineToPoint:q] : [p moveToPoint:q];
    }
    [p closePath];
    p.lineJoinStyle = NSLineJoinStyleRound;
    p.lineWidth = k * 1.1;
    return p;
}

// 图案：主题色底板上一块白色竖屏，一个小指针一半压在竖屏右下方
static void drawSymbol(void) {
    NSRect base = NSMakeRect(100, 100, 824, 824);
    NSColor *ink = RGB(0x5E5CE6, 1);
    [RR(base, 184) addClip];
    [[[NSGradient alloc] initWithStartingColor:RGB(0x6E6BF4, 1) endingColor:RGB(0x5350E0, 1)] drawInRect:base
                                                                                                   angle:-90];

    NSRect ph = NSMakeRect(352, 232, 320, 560);
    NSBezierPath *phone = RR(ph, 76);
    [NSColor.whiteColor setFill];
    [phone fill];

    // 指针像系统光标一样：主题色填充、白色描边，压在竖屏和底板上都看得清
    CGFloat k = 10;
    NSBezierPath *cur = cursorPath(NSMakePoint(NSMaxX(ph) - 4.5 * k, NSMinY(ph) + 300), k);
    cur.lineWidth = k * 2.2;
    [NSColor.whiteColor setStroke];
    [cur stroke];
    [ink setFill];
    [cur fill];
}

static void drawIcon(CGFloat S) {
    NSAffineTransform *t = [NSAffineTransform transform];
    [t scaleBy:S / 1024.0];
    [NSGraphicsContext saveGraphicsState];
    [t concat];
    drawSymbol();
    [NSGraphicsContext restoreGraphicsState];
}

void renderIcons(NSString *dir) {
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    int sizes[] = {16, 32, 128, 256, 512};
    for (int i = 0; i < 5; i++) {
        for (int sc = 1; sc <= 2; sc++) {
            int px = sizes[i] * sc;
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                            pixelsWide:px
                                                                            pixelsHigh:px
                                                                         bitsPerSample:8
                                                                       samplesPerPixel:4
                                                                              hasAlpha:YES
                                                                              isPlanar:NO
                                                                        colorSpaceName:NSDeviceRGBColorSpace
                                                                           bytesPerRow:0
                                                                          bitsPerPixel:0];
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
            drawIcon(px);
            [NSGraphicsContext restoreGraphicsState];
            NSString *name = sc == 1 ? [NSString stringWithFormat:@"icon_%dx%d.png", sizes[i], sizes[i]]
                                     : [NSString stringWithFormat:@"icon_%dx%d@2x.png", sizes[i], sizes[i]];
            [[rep representationUsingType:NSBitmapImageFileTypePNG
                               properties:@{}] writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES];
        }
    }
}
