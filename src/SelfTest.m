#import "SelfTest.h"
#import "DisplayControl.h"
#import "PhoneModels.h"

static int failures;

static void check(BOOL ok, NSString *what) {
    printf("%s  %s\n", ok ? "通过" : "失败", what.UTF8String);
    fflush(stdout);
    if (!ok) {
        failures++;
    }
}

static void after(double sec, void (^block)(void)) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sec * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

static BOOL mainDisplayIs(size_t w, size_t h) {
    CGDirectDisplayID d = CGMainDisplayID();
    return CGDisplayPixelsWide(d) == w && CGDisplayPixelsHigh(d) == h;
}

static BOOL hasRestoreRecord(void) {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"restore"] != nil;
}

void selfTestSchedule(AppDelegate *app) {
    // 启动前主屏的尺寸，关闭后应该回到这里
    size_t w0 = CGDisplayPixelsWide(CGMainDisplayID());
    size_t h0 = CGDisplayPixelsHigh(CGMainDisplayID());
    __block int w = 0, h = 0, w2 = 0;

    after(3.0, ^{
        w = app.currentW;
        h = app.currentH;
        w2 = w < WMAX ? w + STEP : w - STEP;
        check(displayIsOn() && displayIsMirrored(), @"启动后虚拟屏已开启并设好镜像");
        check(mainDisplayIs(w, h), [NSString stringWithFormat:@"主屏是 %d×%d", w, h]);
        check(hasRestoreRecord(), @"恢复记录已写入");
        [app setW:w2 h:h];
    });
    after(5.2, ^{
        check(mainDisplayIs(w2, h), [NSString stringWithFormat:@"调整后主屏是 %d×%d", w2, h]);
        [app setW:w h:h];
    });
    after(6.6, ^{
        [app setRemoteOn:NO];
        check(displayIsClosing(), @"点关闭后进入正在关闭");
    });
    after(9.4, ^{
        check(!displayIsOn() && !displayIsClosing(), @"关闭完成");
        check(mainDisplayIs(w0, h0), [NSString stringWithFormat:@"主屏回到 %zu×%zu", w0, h0]);
        check(!hasRestoreRecord(), @"恢复记录已清除");
    });
    after(10.2, ^{
        [app setRemoteOn:YES];
    });
    after(12.8, ^{
        check(displayIsOn() && displayIsMirrored() && mainDisplayIs(w, h), @"再次开启成功");
        printf("%s\n", failures ? [NSString stringWithFormat:@"自测结果：%d 项失败", failures].UTF8String
                                : "自测结果：全部通过（退出后请确认显示器已恢复）");
        fflush(stdout);
        [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0 inModes:@[ NSRunLoopCommonModes ]];
    });
}
