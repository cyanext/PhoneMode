#import <Cocoa/Cocoa.h>
// README 顶部的远程示意图（docs/remote-diagram.jpg）。生成：
//   clang -fobjc-arc -o /tmp/diagram tools/diagram.m -framework Cocoa && /tmp/diagram /tmp/diagram.png
//   sips -s format jpeg -s formatOptions 88 /tmp/diagram.png --out docs/remote-diagram.jpg
// 左边显示器（远程画面按手机比例居中，两侧黑边），右边手机全屏（状态栏以下整块都是同一块远程画面）。
// 远程画面是一块竖着的桌面：壁纸、菜单栏、左侧程序坞、浅色终端窗口，里面和 agent 对话。内容都是编的，设备和图标是通用造型
#define W 1600
#define H 900
static NSColor *hx(unsigned v, CGFloat a){ return [NSColor colorWithSRGBRed:((v>>16)&255)/255.0 green:((v>>8)&255)/255.0 blue:(v&255)/255.0 alpha:a]; }
static NSDictionary *font(CGFloat size, NSFontWeight w, NSColor *c) { return @{NSFontAttributeName:[NSFont systemFontOfSize:size weight:w], NSForegroundColorAttributeName:c}; }
static CGFloat say(NSString *s, CGFloat x, CGFloat y, CGFloat size, NSColor *c, NSFontWeight w) {
    NSDictionary *a = font(size, w, c); [s drawAtPoint:NSMakePoint(x, y) withAttributes:a]; return [s sizeWithAttributes:a].width;
}
static void csay(NSString *s, CGFloat cx, CGFloat y, CGFloat size, NSColor *c, NSFontWeight w) {
    NSDictionary *a = font(size, w, c); [s drawAtPoint:NSMakePoint(cx - [s sizeWithAttributes:a].width / 2, y) withAttributes:a];
}
#define MONO 15.0
static CGFloat mono(NSString *s, CGFloat x, CGFloat y, NSColor *c) {
    NSDictionary *a = @{NSFontAttributeName:[NSFont monospacedSystemFontOfSize:MONO weight:NSFontWeightRegular], NSForegroundColorAttributeName:c};
    [s drawAtPoint:NSMakePoint(x, y) withAttributes:a];
    return [s sizeWithAttributes:a].width;
}
static NSBezierPath *rr(NSRect r, CGFloat k) { return [NSBezierPath bezierPathWithRoundedRect:r xRadius:k yRadius:k]; }
static void shadowed(CGFloat blur, CGFloat dy, CGFloat a, void (^d)(void)) {
    [NSGraphicsContext saveGraphicsState];
    NSShadow *s = [NSShadow new]; s.shadowBlurRadius = blur; s.shadowOffset = NSMakeSize(0, dy); s.shadowColor = [NSColor colorWithWhite:0 alpha:a]; [s set];
    d(); [NSGraphicsContext restoreGraphicsState];
}

// 远程画面：按 400×800 设计，坐标原点在左上角
#define CW 400.0
#define CH 800.0
#define DOCK_W 46.0
// 程序坞里的一枚图标：渐变圆角方块上一个白色符号
static void dockIcon(NSRect r, unsigned c1, unsigned c2, NSString *sym) {
    shadowed(4, 1.5, 0.25, ^{ [hx(c1,1) setFill]; [rr(r, 8) fill]; });
    [[[NSGradient alloc] initWithStartingColor:hx(c1,1) endingColor:hx(c2,1)] drawInBezierPath:rr(r, 8) angle:90];
    NSImage *im = [NSImage imageWithSystemSymbolName:sym accessibilityDescription:nil];
    im = [im imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[ NSColor.whiteColor ]]];
    NSSize sz = im.size; CGFloat k = 17 / MAX(sz.width, sz.height);
    [im drawInRect:NSMakeRect(NSMidX(r) - sz.width * k / 2, NSMidY(r) - sz.height * k / 2, sz.width * k, sz.height * k)];
}
static NSImage *remoteScreen(void) {
    return [NSImage imageWithSize:NSMakeSize(CW, CH) flipped:YES drawingHandler:^BOOL(NSRect r) {
        [[[NSGradient alloc] initWithColorsAndLocations:hx(0x7FA6F5,1), 0.0, hx(0xA88BE8,1), 0.55, hx(0xF2A7B8,1), 1.0, nil] drawInRect:r angle:60];
        [hx(0xFFFFFF,0.6) setFill]; NSRectFillUsingOperation(NSMakeRect(0, 0, CW, 18), NSCompositingOperationSourceOver);
        CGFloat x = 10;
        for (NSString *m in @[@"终端", @"Shell", @"编辑", @"显示", @"窗口"]) x += say(m, x, 2, 10.5, hx(0x1D1D1F,1), [m isEqualToString:@"终端"] ? NSFontWeightBold : NSFontWeightRegular) + 12;
        say(@"周二 15:20", CW - 64, 2, 10.5, hx(0x1D1D1F,1), NSFontWeightRegular);
        // 左侧程序坞：竖着一列图标，正在运行的右边带小圆点
        NSRect dock = NSMakeRect(4, 200, DOCK_W, 330);
        shadowed(10, 3, 0.18, ^{ [hx(0xFFFFFF,0.42) setFill]; [rr(dock, 14) fill]; });
        [hx(0xFFFFFF,0.55) setStroke]; NSBezierPath *db = rr(NSInsetRect(dock, 0.5, 0.5), 13.5); db.lineWidth = 1; [db stroke];
        unsigned c1s[] = {0x5AC8FA, 0x34C759, 0x1C1E26, 0x007AFF, 0xFF9500, 0xAF52DE, 0x8E8E93};
        unsigned c2s[] = {0x1E88E5, 0x1FA347, 0x3A3D47, 0x0051D5, 0xFF6A00, 0x7B2FBE, 0x5E5E63};
        NSArray *syms = @[ @"face.smiling", @"message.fill", @"terminal.fill", @"globe", @"note.text", @"music.note", @"gearshape.fill" ];
        for (int i = 0; i < 7; i++) {
            NSRect ic = NSMakeRect(dock.origin.x + 7, dock.origin.y + 10 + i * 45, 32, 32);
            dockIcon(ic, c1s[i], c2s[i], syms[i]);
            if (i == 0 || i == 2) { [hx(0x1D1D1F,0.8) setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMaxX(dock) - 4.5, NSMidY(ic) - 1.5, 3, 3)] fill]; }
        }
        // 浅色终端窗口：在程序坞右边占满
        NSRect win = NSMakeRect(DOCK_W + 10, 26, CW - DOCK_W - 16, CH - 34);
        shadowed(16, 6, 0.28, ^{ [hx(0xFFFFFF,1) setFill]; [rr(win, 10) fill]; });
        [NSGraphicsContext saveGraphicsState]; [rr(win, 10) addClip];
        [hx(0xECECEE,1) setFill]; NSRectFill(NSMakeRect(win.origin.x, win.origin.y, win.size.width, 28));
        [hx(0xD4D4D8,1) setFill]; NSRectFill(NSMakeRect(win.origin.x, win.origin.y + 28, win.size.width, 1));
        unsigned dots[] = {0xFF5F57, 0xFEBC2E, 0x28C840};
        for (int i = 0; i < 3; i++) { [hx(dots[i],1) setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(win.origin.x + 12 + i * 16, win.origin.y + 9, 10, 10)] fill]; }
        csay(@"shop-web — zsh", NSMidX(win) + 20, win.origin.y + 7, 11.5, hx(0x6E6E73,1), NSFontWeightMedium);
        NSColor *dim = hx(0x8A8F98,1), *fg = hx(0x1F2329,1), *green = hx(0x1A9E4B,1), *blue = hx(0x2F6FDE,1), *yellow = hx(0xB7791F,1), *add = hx(0x1A7F37,1), *del = hx(0xCF222E,1);
        CGFloat x0 = win.origin.x + 12, y = win.origin.y + 42, lh = 24;
        CGFloat w;
        w = mono(@"~/shop-web", x0, y, blue); mono(@" on main", x0 + w, y, dim); y += lh;
        w = mono(@"$ ", x0, y, green); mono(@"claude", x0 + w, y, fg); y += lh * 1.4;
        w = mono(@"> ", x0, y, yellow); mono(@"订单页下单后白屏，看下", x0 + w, y, fg); y += lh * 1.4;
        w = mono(@"● ", x0, y, green); mono(@"报错在 OrderList.tsx：", x0 + w, y, fg); y += lh;
        mono(@"  超时时 items 是 undefined。", x0, y, fg); y += lh * 1.4;
        w = mono(@"● ", x0, y, green); mono(@"修改 OrderList.tsx", x0 + w, y, fg); y += lh;
        mono(@"  - items.map(row)", x0, y, del); y += lh;
        mono(@"  + (items ?? []).map(row)", x0, y, add); y += lh * 1.4;
        w = mono(@"● ", x0, y, green); mono(@"已修复，刷新页面试试。", x0 + w, y, fg); y += lh * 1.4;
        w = mono(@"> ", x0, y, yellow); mono(@"好了，再加个空状态", x0 + w, y, fg); y += lh * 1.4;
        w = mono(@"● ", x0, y, green); mono(@"新增 Empty.tsx", x0 + w, y, fg); y += lh;
        mono(@"  + export function Empty() {", x0, y, add); y += lh;
        mono(@"  +   return <p>还没有订单</p>;", x0, y, add); y += lh;
        mono(@"  + }", x0, y, add); y += lh * 1.4;
        w = mono(@"● ", x0, y, green); mono(@"运行测试", x0 + w, y, fg); y += lh;
        mono(@"  ✓ 12 passed (1.8s)", x0, y, green); y += lh * 1.4;
        w = mono(@"● ", x0, y, green); mono(@"空状态加好了。", x0 + w, y, fg); y += lh * 1.4;
        w = mono(@"> ", x0, y, yellow);
        [fg setFill]; NSRectFill(NSMakeRect(x0 + w + 1, y + 1, 8, 18));
        [NSGraphicsContext restoreGraphicsState];
        return YES;
    }];
}

int main(int argc, const char **argv){ @autoreleasepool {
  NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W * 2 pixelsHigh:H * 2 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
  rep.size = NSMakeSize(W, H);
  [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
  [[[NSGradient alloc] initWithColorsAndLocations:hx(0xF4F6FB,1), 0.0, hx(0xE9EDF6,1), 1.0, nil] drawInRect:NSMakeRect(0,0,W,H) angle:-90];
  NSImage *screen = remoteScreen();

  NSRect mon = NSMakeRect(80, 250, 900, 520);
  shadowed(50, -24, 0.28, ^{ [hx(0x1A1B1F,1) setFill]; [rr(mon, 18) fill]; });
  NSRect scr = NSInsetRect(mon, 12, 12);
  [hx(0x000000,1) setFill]; [rr(scr, 7) fill];
  CGFloat ch = scr.size.height, cw = ch * CW / CH;
  [screen drawInRect:NSMakeRect(NSMidX(scr) - cw / 2, scr.origin.y, cw, ch)];
  NSBezierPath *neck = [NSBezierPath bezierPath];
  [neck moveToPoint:NSMakePoint(NSMidX(mon) - 46, mon.origin.y)]; [neck lineToPoint:NSMakePoint(NSMidX(mon) + 46, mon.origin.y)];
  [neck lineToPoint:NSMakePoint(NSMidX(mon) + 62, 132)]; [neck lineToPoint:NSMakePoint(NSMidX(mon) - 62, 132)]; [neck closePath];
  [[[NSGradient alloc] initWithStartingColor:hx(0xC9CCD2,1) endingColor:hx(0x9EA2AA,1)] drawInBezierPath:neck angle:0];
  NSRect base = NSMakeRect(NSMidX(mon) - 170, 116, 340, 18);
  shadowed(24, -8, 0.25, ^{ [hx(0xB9BCC3,1) setFill]; [rr(base, 9) fill]; });
  [[[NSGradient alloc] initWithStartingColor:hx(0xDADDE2,1) endingColor:hx(0xA9ADB5,1)] drawInBezierPath:rr(base, 9) angle:-90];
  csay(@"电脑上：画面按手机比例显示，两侧留黑边", NSMidX(mon), 60, 20, hx(0x3A3F47,1), NSFontWeightMedium);

  NSRect ph = NSMakeRect(1150, 54, 360, 780);
  shadowed(50, -24, 0.3, ^{ [hx(0x1A1B1F,1) setFill]; [rr(ph, 58) fill]; });
  [hx(0x3A3B40,1) setStroke]; NSBezierPath *rim = rr(NSInsetRect(ph, 1.5, 1.5), 56.5); rim.lineWidth = 3; [rim stroke];
  NSRect ps = NSInsetRect(ph, 11, 11);
  [NSGraphicsContext saveGraphicsState]; [rr(ps, 48) addClip];
  [hx(0xF6F7F9,1) setFill]; NSRectFill(ps);
  CGFloat top = NSMaxY(ps);
  say(@"15:20", ps.origin.x + 34, top - 38, 16, hx(0x111111,1), NSFontWeightSemibold);
  [hx(0x050505,1) setFill]; [rr(NSMakeRect(NSMidX(ps) - 46, top - 44, 92, 28), 14) fill];
  for (int i = 0; i < 4; i++) { [hx(0x111111,1) setFill]; [rr(NSMakeRect(NSMaxX(ps) - 104 + i * 6, top - 34, 4, 5 + i * 2.5), 1) fill]; }
  [[NSImage imageWithSystemSymbolName:@"wifi" accessibilityDescription:nil] drawInRect:NSMakeRect(NSMaxX(ps) - 74, top - 35, 17, 13)];
  [[NSImage imageWithSystemSymbolName:@"battery.75percent" accessibilityDescription:nil] drawInRect:NSMakeRect(NSMaxX(ps) - 52, top - 35, 27, 13)];
  // 状态栏以下、手势条以上整块都是远程画面
  NSRect area = NSMakeRect(ps.origin.x, ps.origin.y + 22, ps.size.width, top - 54 - ps.origin.y - 22);
  [screen drawInRect:area fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
  [hx(0x1F2329,1) setFill]; [rr(NSMakeRect(NSMidX(ps) - 60, ps.origin.y + 8, 120, 5), 2.5) fill];
  [NSGraphicsContext restoreGraphicsState];
  csay(@"手机上：画面铺满整块屏幕", NSMidX(ph), 14, 20, hx(0x3A3F47,1), NSFontWeightMedium);

  CGFloat ay = 470;
  NSBezierPath *line = [NSBezierPath bezierPath];
  [line moveToPoint:NSMakePoint(1000, ay)]; [line lineToPoint:NSMakePoint(1118, ay)];
  CGFloat dash[] = {2, 9}; [line setLineDash:dash count:2 phase:0];
  line.lineWidth = 4; line.lineCapStyle = NSLineCapStyleRound; [hx(0x3D6FF2,1) setStroke]; [line stroke];
  NSBezierPath *head = [NSBezierPath bezierPath];
  [head moveToPoint:NSMakePoint(1132, ay)]; [head lineToPoint:NSMakePoint(1116, ay + 11)]; [head lineToPoint:NSMakePoint(1116, ay - 11)]; [head closePath];
  [hx(0x3D6FF2,1) setFill]; [head fill];
  NSRect chip = NSMakeRect(1010, ay + 20, 112, 34);
  shadowed(10, -3, 0.12, ^{ [NSColor.whiteColor setFill]; [rr(chip, 17) fill]; });
  csay(@"远程连接", NSMidX(chip), chip.origin.y + 8, 15, hx(0x3D6FF2,1), NSFontWeightSemibold);

  [NSGraphicsContext restoreGraphicsState];
  [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argc > 1 ? argv[1] : "diagram.png") atomically:YES];
}}
