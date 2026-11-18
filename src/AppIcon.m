#import "AppIcon.h"
#import "Theme.h"

// 图标都按 1024 的画布来画，再整体缩放到目标尺寸；坐标原点在左下角

// 图案：白色底板中间一道紫色折线，表示连接，和菜单栏图标同形
static void drawSymbol(void) {
    NSRect base = NSMakeRect(100, 100, 824, 824);
    NSBezierPath *plate = RR(base, 184);

    // 白底在浅色 Dock 上容易糊成一片：加一层轻投影和一圈细描边
    NSShadow *sh = [NSShadow new];
    sh.shadowColor = RGB(0x000000, 0.18);
    sh.shadowOffset = NSMakeSize(0, -10);
    sh.shadowBlurRadius = 28;
    [NSGraphicsContext saveGraphicsState];
    [sh set];
    [NSColor.whiteColor setFill];
    [plate fill];
    [NSGraphicsContext restoreGraphicsState];

    [NSGraphicsContext saveGraphicsState];
    [plate addClip];
    [[[NSGradient alloc] initWithStartingColor:RGB(0xFFFFFF, 1) endingColor:RGB(0xEEEEF3, 1)] drawInRect:base
                                                                                                   angle:-90];
    [NSGraphicsContext restoreGraphicsState];
    NSBezierPath *edge = RR(NSInsetRect(base, 1.5, 1.5), 182.5);
    edge.lineWidth = 3;
    [RGB(0x000000, 0.08) setStroke];
    [edge stroke];

    // 折线和菜单栏图标同一形状：18 格里 (4.5,7.5) → (8,11) → (10,7) → (13.5,10.5)，放大到底板里
    CGFloat k = 824 / 18.0 * 0.95, o = 512 - 9 * k;
    CGFloat pts[][2] = {{4.5, 7.5}, {8, 11}, {10, 7}, {13.5, 10.5}};
    NSBezierPath *line = [NSBezierPath bezierPath];
    for (int i = 0; i < 4; i++) {
        NSPoint q = NSMakePoint(o + pts[i][0] * k, o + pts[i][1] * k);
        i ? [line lineToPoint:q] : [line moveToPoint:q];
    }
    line.lineWidth = 1.8 * k;
    line.lineCapStyle = NSLineCapStyleRound;
    line.lineJoinStyle = NSLineJoinStyleRound;
    [RGB(0x5E5CE6, 1) setStroke];
    [line stroke];
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
