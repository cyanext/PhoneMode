// 跟随网易 UU 远程：有人连进来时 UU 的服务进程（UURemoteServer）会在最顶层盖一个全屏的提示框窗口，
// 断开后撤掉。定时看这个窗口在不在，就知道当前有没有远程连接。读窗口列表不需要额外权限
#import <Cocoa/Cocoa.h>

// 开始定时检查。连接状态变化时回调 connected
void uuWatchStart(void (^changed)(BOOL connected));
