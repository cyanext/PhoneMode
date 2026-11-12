#import "Theme.h"

NSColor *RGB(int hex, double a) {
    return [NSColor colorWithSRGBRed:((hex >> 16) & 255) / 255.0
                               green:((hex >> 8) & 255) / 255.0
                                blue:(hex & 255) / 255.0
                               alpha:a];
}

NSBezierPath *RR(NSRect r, CGFloat rad) {
    return [NSBezierPath bezierPathWithRoundedRect:r xRadius:rad yRadius:rad];
}

BOOL isDark(NSView *v) {
    return
        [[v.effectiveAppearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]]
            isEqualToString:NSAppearanceNameDarkAqua];
}

// 主题色：靛紫。THEME 用作实心底（上面压白字），ThemeInk 用作文字、图标和焦点环，深色下换成更亮的一档
NSColor *Dyn(int light, int dark) {
    return [NSColor colorWithName:nil
                  dynamicProvider:^NSColor *(NSAppearance *a) {
                      BOOL d =
                          [[a bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]]
                              isEqualToString:NSAppearanceNameDarkAqua];
                      return RGB(d ? dark : light, 1);
                  }];
}

NSColor *ThemeA(CGFloat a) {
    return RGB(THEME, a);
}

NSColor *ThemeInk(void) {
    return Dyn(0x4F4CD9, 0xA09EFF);
}

// 卡片、关闭态的电源圆
NSColor *Surface(void) {
    return Dyn(0xFFFFFF, 0x2B2B30);
}

// 窗口底
NSColor *Backdrop(void) {
    return Dyn(0xF2F2F7, 0x1C1C1F);
}

// 分段控件和步进器的底槽
NSColor *Track(void) {
    return Dyn(0xE9E9EF, 0x1E1E22);
}

// 分段控件的滑块
NSColor *Thumb(void) {
    return Dyn(0xFFFFFF, 0x3F3F47);
}

// 取一枚 SF Symbol，指定字号、字重和颜色
NSImage *Sym(NSString *name, CGFloat pt, NSFontWeight wt, NSColor *c) {
    NSImage *im = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    if (!im) {
        return nil;
    }
    NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:pt weight:wt];
    if (c) {
        cfg = [cfg
            configurationByApplyingConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:c]];
    }
    return [im imageWithSymbolConfiguration:cfg];
}

void DrawImg(NSImage *im, NSPoint center, CGFloat alpha) {
    if (!im) {
        return;
    }
    NSSize s = im.size;
    [im drawInRect:NSMakeRect(center.x - s.width / 2, center.y - s.height / 2, s.width, s.height)
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:alpha
        respectFlipped:YES
                 hints:nil];
}

NSColor *Ink(CGFloat a) {
    return [NSColor.labelColor colorWithAlphaComponent:a];
}
