// 自测：真实开一次虚拟屏，依次检查开启、调尺寸、关闭、再开启，最后正常退出。会让显示器切换几次
#import "AppDelegate.h"

// 在 [NSApp run] 之前调用；整个过程约 14 秒
void selfTestSchedule(AppDelegate *app);
