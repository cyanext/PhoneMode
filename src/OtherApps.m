#import "OtherApps.h"
#import "DisplayControl.h"

// 会和远程模式抢镜像的工具。以后遇到别的，加进这里
static NSString *const kConflictIDs[] = {@"com.crisp.app", @"pro.betterdisplay.BetterDisplay"};
#define NCONFLICT (sizeof(kConflictIDs) / sizeof(kConflictIDs[0]))
// 让出来的工具的路径，关掉远程画面后照着打开
#define RELAUNCH_KEY @"relaunchApps"

static BOOL quitting;

BOOL otherAppsQuitting(void) {
    return quitting;
}

static NSArray<NSRunningApplication *> *runningConflicts(void) {
    NSMutableArray *out = [NSMutableArray array];
    for (size_t i = 0; i < NCONFLICT; i++) {
        [out addObjectsFromArray:[NSRunningApplication runningApplicationsWithBundleIdentifier:kConflictIDs[i]]];
    }
    return out;
}

// 还有显示器在镜像别的屏，说明对方的虚拟屏还没撤干净
static BOOL anyMirroring(void) {
    uint32_t n = 0;
    CGDirectDisplayID ids[16];
    if (CGGetOnlineDisplayList(16, ids, &n) != kCGErrorSuccess) {
        return NO;
    }
    for (uint32_t i = 0; i < n; i++) {
        if (CGDisplayMirrorsDisplay(ids[i]) != kCGNullDirectDisplay) {
            return YES;
        }
    }
    return NO;
}

// 每 0.25 秒看一次：都退出了、镜像也解除了，再等 0.5 秒让物理屏切回自己的模式。最多等 8 秒，超时也往下走
static void waitGone(NSArray<NSRunningApplication *> *apps, CFAbsoluteTime t0, CFAbsoluteTime settledAt,
                     void (^ready)(void)) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    BOOL gone = YES;
    for (NSRunningApplication *a in apps) {
        gone &= a.terminated;
        // 有时退出请求没被响应：每 2 秒再请求一次，5 秒后还在就强制结束。它的虚拟屏随进程一起撤掉
        if (!a.terminated) {
            double waited = now - t0;
            if (waited > 5) {
                [a forceTerminate];
            } else if (fmod(waited, 2) < 0.25 && waited > 1) {
                [a terminate];
            }
        }
    }
    gone &= !anyMirroring();
    if (!gone) {
        settledAt = 0;
    } else if (!settledAt) {
        settledAt = now;
    }
    if ((settledAt && now - settledAt >= 0.5) || now - t0 > 8) {
        quitting = NO;
        ready();
        return;
    }
    // 用运行循环的定时器，理由同 DisplayControl 的 scheduleFinishOff
    NSTimer *t = [NSTimer timerWithTimeInterval:0.25
                                        repeats:NO
                                          block:^(NSTimer *x) {
                                              waitGone(apps, t0, settledAt, ready);
                                          }];
    [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
}

void otherAppsQuitThen(void (^ready)(void)) {
    // 预览模式不碰显示器，也不碰别的程序
    NSArray<NSRunningApplication *> *apps = displayIsPreview() ? @[] : runningConflicts();
    if (!apps.count) {
        ready();
        return;
    }
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSMutableArray *paths = [[ud arrayForKey:RELAUNCH_KEY] ?: @[] mutableCopy];
    for (NSRunningApplication *a in apps) {
        NSString *p = a.bundleURL.path;
        if (p && ![paths containsObject:p]) {
            [paths addObject:p];
        }
        [a terminate];
    }
    [ud setObject:paths forKey:RELAUNCH_KEY];
    [ud synchronize]; // 随后被强杀也还在
    quitting = YES;
    waitGone(apps, CFAbsoluteTimeGetCurrent(), 0, [ready copy]);
}

void otherAppsRelaunch(void) {
    if (displayIsPreview()) {
        return;
    }
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSArray *paths = [ud arrayForKey:RELAUNCH_KEY];
    if (!paths) {
        return;
    }
    [ud removeObjectForKey:RELAUNCH_KEY];
    [ud synchronize];
    for (id p in paths) {
        if (![p isKindOfClass:NSString.class] || ![[NSFileManager defaultManager] fileExistsAtPath:p]) {
            continue;
        }
        // 交给 open 命令去开：退出流程里本程序随后就结束，用 NSWorkspace 异步打开的请求会跟着丢掉。
        // -g 不抢焦点
        NSTask *t = [NSTask new];
        t.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"];
        t.arguments = @[ @"-g", p ];
        [t launchAndReturnError:nil];
    }
}
