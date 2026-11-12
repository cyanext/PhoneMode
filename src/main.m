// 远程模式：建一块 Retina 虚拟屏设为主屏，原主屏镜像它，让手机竖屏远程时 Mac 画面贴合输入法上方的区域
//
// 命令行参数（都是开发和测试用的，平时双击打开不需要）：
//   --render-icon <目录>      只把图标各档尺寸的 PNG 写到目录里，然后退出
//   --quit-after <秒>         到时间自动退出，退出前照常恢复显示器
//   --appearance light|dark   强制浅色或深色外观（截图用）
//   --selftest                跑一遍自测，见 SelfTest.h
//   --preview                 只显示界面，不碰显示器（改界面时截图用，可以和正式版同时开）
#import "AppDelegate.h"
#import "AppIcon.h"
#import "DisplayControl.h"
#import "SelfTest.h"

// 从主队列的块（信号、定时退出）里要退出时，转到运行循环里再调 terminate:。
// 退出要等显示器恢复完成，直接在块里调的话这个块不返回，主队列就不会再执行别的块
static void quitSoon(void) {
    [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0 inModes:@[ NSRunLoopCommonModes ]];
}

static dispatch_source_t signalSources[3];

// 收到 SIGINT、SIGTERM、SIGHUP 时走正常退出流程，显示器才能恢复
static void handleSignals(void) {
    int sigs[3] = {SIGINT, SIGTERM, SIGHUP};
    for (int i = 0; i < 3; i++) {
        signal(sigs[i], SIG_IGN);
        signalSources[i] = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, sigs[i], 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(signalSources[i], ^{
            quitSoon();
        });
        dispatch_resume(signalSources[i]);
    }
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        NSString *iconDir = nil, *appearance = nil;
        int quitAfter = 0;
        BOOL selfTest = NO;
        for (int i = 1; i < argc; i++) {
            NSString *arg = @(argv[i]);
            NSString *value = i + 1 < argc ? @(argv[i + 1]) : nil;
            if ([arg isEqualToString:@"--render-icon"] && value) {
                iconDir = value;
                i++;
            } else if ([arg isEqualToString:@"--quit-after"] && value) {
                quitAfter = value.intValue;
                i++;
            } else if ([arg isEqualToString:@"--appearance"] && value) {
                appearance = value;
                i++;
            } else if ([arg isEqualToString:@"--selftest"]) {
                selfTest = YES;
            } else if ([arg isEqualToString:@"--preview"]) {
                displaySetPreview();
            }
        }
        if (iconDir) {
            renderIcons(iconDir);
            return 0;
        }

        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        if ([appearance isEqualToString:@"dark"]) {
            app.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        } else if ([appearance isEqualToString:@"light"]) {
            app.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        }
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        handleSignals();
        if (quitAfter > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)quitAfter * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                               quitSoon();
                           });
        }
        if (selfTest) {
            selfTestSchedule(delegate);
        }
        [app run];
    }
    return 0;
}
