// 主题色、底色和几个绘图小工具
#import <Cocoa/Cocoa.h>

// 主题色：靛紫。THEME 用作实心底（上面压白字），ThemeInk 用作文字、图标和焦点环
#define THEME 0x5E5CE6

NSColor *RGB(int hex, double a);
NSBezierPath *RR(NSRect r, CGFloat rad);
BOOL isDark(NSView *v);
// 浅色、深色各给一个色值，随外观自动切换
NSColor *Dyn(int light, int dark);
NSColor *ThemeA(CGFloat a);
NSColor *ThemeInk(void);
NSColor *Surface(void);
NSColor *Backdrop(void);
NSColor *Track(void);
NSColor *Thumb(void);
// 文字色按透明度取一档，用作中性的浅底
NSColor *Ink(CGFloat a);
// 取一枚 SF Symbol，指定字号、字重和颜色
NSImage *Sym(NSString *name, CGFloat pt, NSFontWeight wt, NSColor *c);
void DrawImg(NSImage *im, NSPoint center, CGFloat alpha);
