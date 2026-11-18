// 颜色和绘图小工具
#import <Cocoa/Cocoa.h>

NSColor *RGB(int hex, double a);
NSBezierPath *RR(NSRect r, CGFloat rad);
// 行图标的圆形灰底，随深浅色切换
NSColor *ChipFill(void);
