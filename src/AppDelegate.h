// 主程序：菜单栏图标和面板、设置存取、预设、退出时的恢复
#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate, NSPopoverDelegate>
// 当前的虚拟屏宽高（点）
@property(readonly) int currentW, currentH;
// 设宽高：夹到允许范围，刷新界面，稍后应用到虚拟屏并保存
- (void)setW:(int)w h:(int)h;
// 开或关远程画面
- (void)setRemoteOn:(BOOL)on;
@end
