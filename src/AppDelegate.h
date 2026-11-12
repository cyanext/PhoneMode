// 主程序：窗口、设置存取、预设、Dock 菜单和退出时的恢复
#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate>
// 当前的虚拟屏宽高（点）
@property(readonly) int currentW, currentH;
// 设宽高：夹到允许范围，刷新界面，稍后应用到虚拟屏并保存
- (void)setW:(int)w h:(int)h;
// 开或关远程画面（窗口按钮和 Dock 菜单共用）
- (void)setRemoteOn:(BOOL)on;
@end
