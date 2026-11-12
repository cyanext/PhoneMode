// 显示器控制：建一块 Retina 虚拟屏设为主屏，让原主屏镜像它；关闭时解除镜像并把物理屏恢复原模式
#import <Cocoa/Cocoa.h>

// 开启。成功或已经开着返回 YES；正在关闭、私有类取不到、创建失败返回 NO
BOOL displayOn(int w, int h);
// 改虚拟屏尺寸，没开时什么也不做
void displayResize(int w, int h);
// 关闭：解除镜像后等 1.5 秒再恢复原模式，等待期间不占主线程；全部做完后调用 done
void displayOff(void (^done)(void));
// 兜底的同步关闭：退出流程没等到异步恢复完成时用
void displayOffSync(void);
// 虚拟屏丢失后不再重建：只把物理屏恢复原样
void displayAbandon(void);
// 启动时调用：上次被强杀或崩溃、物理屏没恢复时先切回记录的模式。返回是否做了恢复
BOOL displayRecoverFromCrash(void);
// 稍等片刻后确认虚拟屏还在不在（唤醒、显示器配置变化时调用）
void displayScheduleVerify(void);

// 预览模式（--preview）：界面照常，开关只是假装，不建虚拟屏、不改任何显示器。要在其他调用之前设
void displaySetPreview(void);

BOOL displayIsOn(void);
BOOL displayIsMirrored(void);
BOOL displayIsClosing(void);
// 镜像设好、或虚拟屏被系统回收（lost 为 YES）时回调
void displaySetEventHandler(void (^handler)(BOOL lost));
