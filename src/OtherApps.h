// 和其他虚拟屏工具共处：Crisp、BetterDisplay 这类工具也靠「建虚拟屏、让物理屏镜像它」工作，和远程模式同时开会互相抢镜像，
// 指针会丢、退出后分辨率回不去。所以开远程画面前先让它们退出，关掉后再把它们打开，由它们自己恢复设置
#import <Cocoa/Cocoa.h>

// 有冲突的工具在运行：让它们退出，等它们的虚拟屏下线、物理屏稳定后调用 ready；
// 没有在运行就立刻调用。退出了哪些会记进设置，程序被强杀后下次也能把它们打开
void otherAppsQuitThen(void (^ready)(void));
// 把之前让出来的工具重新打开（不抢焦点），然后清掉记录。没有记录时什么也不做，可以重复调用
void otherAppsRelaunch(void);
// 正在等它们退出
BOOL otherAppsQuitting(void);
