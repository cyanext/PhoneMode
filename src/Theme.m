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

// 浅色、深色各给一个色值，随外观自动切换
static NSColor *Dyn(int light, int dark) {
    return [NSColor colorWithName:nil
                  dynamicProvider:^NSColor *(NSAppearance *a) {
                      BOOL d =
                          [[a bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]]
                              isEqualToString:NSAppearanceNameDarkAqua];
                      return RGB(d ? dark : light, 1);
                  }];
}

NSColor *ChipFill(void) {
    return Dyn(0xE5E5EA, 0x3A3A3C);
}
