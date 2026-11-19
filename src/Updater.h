// 从 GitHub Releases 检查更新：启动后查一次、之后每天一次，也可以手动查。
// 有新版弹提示，点「更新」就下载 Release 里的 zip、解压、退出本程序、替换程序包、重新打开。
// PicBox 和远程模式共用这份代码，两边各放一份，改的时候一起改
#import <Cocoa/Cocoa.h>

@interface Updater : NSObject
+ (instancetype)shared;
// repo 形如 @"cyanext/PicBox"。不是从 .app 里运行的（比如开发时直接跑二进制）不检查
- (void)startWithRepo:(NSString *)repo;
// 现在能不能装：返回 NO 时先下载好等着，程序自己在合适的时候调 installPendingIfReady
@property(copy) BOOL (^canInstallNow)(void);
// 手动检查：没有新版、检查失败也弹提示
- (void)checkNow;
// 之前因为不能装而等着的更新，现在装
- (void)installPendingIfReady;
@end
