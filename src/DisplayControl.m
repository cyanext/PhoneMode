#import "Localize.h"
#import "DisplayControl.h"
#import "CGVirtualDisplay.h"
#import "PhoneModels.h"

static CGVirtualDisplay *vd;              // 当前虚拟屏；nil 表示没开
static BOOL mirrored;                     // 镜像已经设好
static BOOL closing;                      // 正在关闭：镜像已解除，等虚拟屏下线后恢复各物理屏
static unsigned gen;                      // 每建一次虚拟屏加一，用来识别过期的延迟回调
static CFAbsoluteTime createdAt;          // 最近一次建虚拟屏的时间
static NSMutableArray *offWaiters;        // 等关闭完成的回调
static void (^onDisplayEvent)(BOOL lost); // 通知界面刷新；lost 表示虚拟屏被系统回收了
static int curW, curH;                    // 虚拟屏应有的尺寸，修复分辨率时用
static SizeRange curRange;                // 档位的范围：手机和电脑不同
// 物理屏怎么恢复（关闭时、崩溃后启动时）：
// 不以开启那一刻的分辨率为准。跟随 UU 时，UU 一连上就先把屏临时降了分辨率，等远程模式开启再拍，拍到的已经是改过的。
// 以用户自己的显示器配置为准：系统按「接了哪几块屏」分组，把每块屏用户选的分辨率存在当前用户、当前主机的偏好里
// （com.apple.windowserver.displays 的 DisplaySets）。系统设置、Crisp 改分辨率会写进去，程序临时改的不会。
// 关闭时按当前接着的物理屏组合查这一组，每块屏切回里面记的分辨率；查不到（新屏没配置过、系统改了存储格式）
// 才用开启前拍的快照。恢复只临时生效（kCGConfigureForSession），不改用户配置，错了也不会被系统记住。
// 镜像设好时记一个标记，恢复后清掉；启动时发现还在，说明上次被强杀或崩溃，同样恢复一次
#define PENDING_KEY @"restorePending"
#define LEGACY_KEY @"restore" // 1.2 及以前记的各屏原分辨率，现在只当作「上次没恢复」的标记
static NSMutableDictionary *snapshot; // 显示器编号 -> 开启前的模式（CGDisplayModeRef），查不到用户配置时用
// 预览模式：只看界面，不碰显示器。开关只改这两个状态
static BOOL preview, previewOn;

void displaySetPreview(void) {
    preview = YES;
}

static CFArrayRef allModes(CGDirectDisplayID d) {
    const void *k[] = {kCGDisplayShowDuplicateLowResolutionModes};
    const void *v[] = {kCFBooleanTrue};
    CFDictionaryRef o = CFDictionaryCreate(NULL, k, v, 1, NULL, NULL);
    CFArrayRef a = CGDisplayCopyAllDisplayModes(d, o);
    CFRelease(o);
    return a;
}

static BOOL displayOnline(CGDirectDisplayID d) {
    uint32_t n = 0;
    CGDirectDisplayID ids[16];
    if (CGGetOnlineDisplayList(16, ids, &n) != kCGErrorSuccess) {
        return YES; // 查不到时当作还在，避免误判
    }
    for (uint32_t i = 0; i < n; i++) {
        if (ids[i] == d) {
            return YES;
        }
    }
    return NO;
}

static void setPending(BOOL on) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (on == [ud boolForKey:PENDING_KEY] && !(!on && [ud objectForKey:LEGACY_KEY])) {
        return;
    }
    [ud setBool:on forKey:PENDING_KEY];
    if (!on) {
        [ud removeObjectForKey:LEGACY_KEY];
    }
    [ud synchronize]; // 立刻落盘，随后被强杀也还在
}

static NSString *uuidOf(CGDirectDisplayID d) {
    CFUUIDRef u = CGDisplayCreateUUIDFromDisplayID(d);
    if (!u) {
        return nil;
    }
    NSString *s = CFBridgingRelease(CFUUIDCreateString(NULL, u));
    CFRelease(u);
    return s.uppercaseString;
}

// 用户配置里，这块屏在 group 这组显示器下记的分辨率（Wide、High、Scale、Hz）。查不到返回 nil
static NSDictionary *userSetting(CGDirectDisplayID d, NSSet *group) {
    id sets = CFBridgingRelease(CFPreferencesCopyValue(CFSTR("DisplaySets"), CFSTR("com.apple.windowserver.displays"),
                                                       kCFPreferencesCurrentUser, kCFPreferencesCurrentHost));
    id configs = [sets isKindOfClass:NSDictionary.class] ? sets[@"Configs"] : nil;
    NSString *me = uuidOf(d);
    for (id c in [configs isKindOfClass:NSArray.class] ? configs : @[]) {
        id list = [c isKindOfClass:NSDictionary.class] ? c[@"DisplayConfig"] : nil;
        if (![list isKindOfClass:NSArray.class]) {
            continue;
        }
        NSMutableSet *ids = [NSMutableSet set];
        id mine = nil;
        for (id e in list) {
            id u = [e isKindOfClass:NSDictionary.class] ? e[@"UUID"] : nil;
            if ([u isKindOfClass:NSString.class]) {
                [ids addObject:[u uppercaseString]];
                if ([[u uppercaseString] isEqualToString:me]) {
                    mine = e[@"CurrentInfo"];
                }
            }
        }
        if ([ids isEqualToSet:group] && [mine isKindOfClass:NSDictionary.class]) {
            return mine;
        }
    }
    return nil;
}

// 显示器里和用户配置对得上的模式：点数宽高、像素宽（宽 × 缩放）相同，刷新率取最接近的。要 CGDisplayModeRelease
static CGDisplayModeRef copyModeFor(CGDirectDisplayID d, NSDictionary *info) {
    int W = [info[@"Wide"] intValue], H = [info[@"High"] intValue], S = MAX(1, [info[@"Scale"] intValue]);
    double R = [info[@"Hz"] doubleValue];
    CFArrayRef a = W > 0 && H > 0 ? allModes(d) : NULL;
    CGDisplayModeRef best = NULL;
    for (CFIndex i = 0; a && i < CFArrayGetCount(a); i++) {
        CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(a, i);
        if ((int)CGDisplayModeGetWidth(m) != W || (int)CGDisplayModeGetHeight(m) != H ||
            (int)CGDisplayModeGetPixelWidth(m) != W * S || !CGDisplayModeIsUsableForDesktopGUI(m)) {
            continue;
        }
        if (!best || fabs(CGDisplayModeGetRefreshRate(m) - R) < fabs(CGDisplayModeGetRefreshRate(best) - R)) {
            best = m;
        }
    }
    if (best) {
        CGDisplayModeRetain(best);
    }
    if (a) {
        CFRelease(a);
    }
    return best;
}

static BOOL sameMode(CGDisplayModeRef a, CGDisplayModeRef b) {
    return a && b && CGDisplayModeGetWidth(a) == CGDisplayModeGetWidth(b) &&
           CGDisplayModeGetHeight(a) == CGDisplayModeGetHeight(b) &&
           CGDisplayModeGetPixelWidth(a) == CGDisplayModeGetPixelWidth(b) &&
           fabs(CGDisplayModeGetRefreshRate(a) - CGDisplayModeGetRefreshRate(b)) < 0.5;
}

// 各物理屏切回用户配置里的分辨率（查不到用快照），一次临时配置完成
static void restoreDisplays(void) {
    uint32_t n = 0;
    CGDirectDisplayID ids[16];
    if (CGGetOnlineDisplayList(16, ids, &n) != kCGErrorSuccess) {
        n = 0;
    }
    NSMutableSet *group = [NSMutableSet set];
    for (uint32_t i = 0; i < n; i++) {
        NSString *u = uuidOf(ids[i]);
        if (u) {
            [group addObject:u];
        }
    }
    CGDisplayConfigRef c;
    BOOL began = CGBeginDisplayConfiguration(&c) == kCGErrorSuccess, changed = NO;
    for (uint32_t i = 0; began && i < n; i++) {
        CGDisplayModeRef m = copyModeFor(ids[i], userSetting(ids[i], group));
        if (!m && snapshot[@(ids[i])]) {
            m = CGDisplayModeRetain((__bridge CGDisplayModeRef)snapshot[@(ids[i])]);
        }
        CGDisplayModeRef cur = CGDisplayCopyDisplayMode(ids[i]);
        if (m && !sameMode(m, cur)) {
            CGConfigureDisplayWithDisplayMode(c, ids[i], m, NULL);
            changed = YES;
        }
        if (cur) {
            CGDisplayModeRelease(cur);
        }
        if (m) {
            CGDisplayModeRelease(m);
        }
    }
    if (began) {
        changed ? CGCompleteDisplayConfiguration(c, kCGConfigureForSession) : CGCancelDisplayConfiguration(c);
    }
    snapshot = nil;
    setPending(NO);
}

// 启动时调用：上次没正常恢复就先恢复一次。返回是否做了恢复
BOOL displayRecoverFromCrash(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (preview || (![ud boolForKey:PENDING_KEY] && ![ud objectForKey:LEGACY_KEY])) {
        return NO;
    }
    restoreDisplays();
    return YES;
}

// 虚拟屏的一组档位：设定的那档，同比例下宽在 curRange 里，同宽度下高 ±300，都每 STEP 一档。
// 拖显示大小、调画面高度只是在档位间切换，系统切得又快又稳；重新定义档位（applySettings）
// 要把虚拟屏和镜像整套重建，开着镜像时一次改动大了会把整机卡住。
// first 不为 0 时把这档排第一个：重新定义档位时让虚拟屏先停在当前这档不动，再切过去。
// 远程软件能切到别的档位，由 enforceTopology 改回来（系统本来也会给虚拟屏补上常见档位）
static CGVirtualDisplaySettings *settingsFor(int w, int h, int firstW, int firstH) {
    CGVirtualDisplaySettings *s = [NSClassFromString(@"CGVirtualDisplaySettings") new];
    Class M = NSClassFromString(@"CGVirtualDisplayMode");
    if (!s || !M) {
        return nil;
    }
    s.hiDPI = 1;
    NSMutableArray *modes = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    // 排第一个的当前档位可能在另一种设备的范围里（手机切电脑），只按总范围卡
    void (^add)(int, int) = ^(int x, int y) {
        NSString *k = [NSString stringWithFormat:@"%dx%d", x, y];
        BOOL keep = x == firstW && y == firstH;
        SizeRange r = keep ? (SizeRange){WMIN, WMAX, HMIN, HMAX} : curRange;
        if (x < r.wmin || x > r.wmax || y < r.hmin || y > r.hmax || [seen containsObject:k]) {
            return;
        }
        [seen addObject:k];
        [modes addObject:[(CGVirtualDisplayMode *)[M alloc] initWithWidth:x height:y refreshRate:60]];
    };
    if (firstW) {
        add(firstW, firstH);
    }
    add(w, h);
    // 和界面上拖显示大小的算法一致：宽度与 w 对齐到 STEP，高度 = 宽度 × 比例四舍五入
    double r = (double)h / w;
    for (int x = w - (w - curRange.wmin) / STEP * STEP; x <= curRange.wmax; x += STEP) {
        add(x, (int)lround(x * r));
    }
    for (int y = h - 300; y <= h + 300; y += STEP) {
        add(w, y);
    }
    s.modes = modes;
    return modes.count ? s : nil;
}

// 虚拟屏可能被系统回收（比如睡眠唤醒后）。显示器配置变化、唤醒、收到终止回调时都来这里，稍等片刻再确认它还在不在
static void verifyDisplay(void);

void displayScheduleVerify(void) {
    if (preview) {
        return;
    }
    static BOOL pending;
    if (pending || !vd) {
        return;
    }
    pending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        pending = NO;
        verifyDisplay();
    });
}

// 除虚拟屏以外的在线显示器，返回块数
static uint32_t physicals(CGDirectDisplayID vid, CGDirectDisplayID out[16]) {
    uint32_t n = 0, k = 0;
    CGDirectDisplayID ids[16];
    if (CGGetOnlineDisplayList(16, ids, &n) != kCGErrorSuccess) {
        return 0;
    }
    for (uint32_t i = 0; i < n; i++) {
        if (ids[i] != vid) {
            out[k++] = ids[i];
        }
    }
    return k;
}

// 是不是设定的尺寸（Retina：像素宽是点数宽的两倍）
static BOOL isWanted(CGDisplayModeRef m) {
    return (int)CGDisplayModeGetWidth(m) == curW && (int)CGDisplayModeGetHeight(m) == curH &&
           (int)CGDisplayModeGetPixelWidth(m) == curW * 2;
}

static BOOL vdModeOK(CGDirectDisplayID vid) {
    CGDisplayModeRef m = CGDisplayCopyDisplayMode(vid);
    if (!m) {
        return YES; // 查不到时不动它
    }
    BOOL ok = isWanted(m);
    CGDisplayModeRelease(m);
    return ok;
}

// 应有的排列：虚拟屏是设定尺寸、在原点当主屏，所有物理屏都镜像它。
// 只要有一块物理屏没进镜像，它就是单独一块屏：Dock 可能跑过去，UU 也要给它单独盖防窥窗口，断开后容易卡住
static BOOL topologyOK(CGDirectDisplayID vid) {
    CGRect b = CGDisplayBounds(vid);
    if (b.origin.x != 0 || b.origin.y != 0 || !vdModeOK(vid)) {
        return NO;
    }
    CGDirectDisplayID p[16];
    uint32_t n = physicals(vid, p);
    for (uint32_t i = 0; i < n; i++) {
        if (CGDisplayMirrorsDisplay(p[i]) != vid) {
            return NO;
        }
    }
    return YES;
}

// 设成应有的排列，只做临时改动（kCGConfigureForSession）
static BOOL applyTopology(CGDirectDisplayID vid) {
    setPending(YES);
    CGDirectDisplayID p[16];
    uint32_t n = physicals(vid, p);
    CGDisplayConfigRef c;
    if (CGBeginDisplayConfiguration(&c) != kCGErrorSuccess) {
        return NO;
    }
    if (!vdModeOK(vid)) {
        CFArrayRef a = allModes(vid);
        for (CFIndex i = 0; a && i < CFArrayGetCount(a); i++) {
            CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(a, i);
            if (isWanted(m)) {
                CGConfigureDisplayWithDisplayMode(c, vid, m, NULL);
                break;
            }
        }
        if (a) {
            CFRelease(a);
        }
    }
    CGConfigureDisplayOrigin(c, vid, 0, 0);
    for (uint32_t i = 0; i < n; i++) {
        CGConfigureDisplayMirrorOfDisplay(c, p[i], vid);
    }
    return CGCompleteDisplayConfiguration(c, kCGConfigureForSession) == kCGErrorSuccess;
}

// 镜像设好之后，外部变化会把排列打乱：插拔显示器，或者别的程序解除镜像、改虚拟屏分辨率。
// 发现了就设回去；一分钟内修满三次还不对，说明在和别的程序来回抢，干脆关掉虚拟屏，Dock 和窗口回到物理屏
static void enforceTopology(void) {
    if (!vd || !mirrored || closing) {
        return;
    }
    CGDirectDisplayID vid = vd.displayID;
    if (topologyOK(vid)) {
        return;
    }
    static CFAbsoluteTime recent[3];
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - recent[0] < 60 || !applyTopology(vid)) {
        NSLog(@"远程模式：显示器排列一直被改掉，关闭虚拟屏");
        displayOff(^{
            if (onDisplayEvent) {
                onDisplayEvent(NO);
            }
        });
        return;
    }
    recent[0] = recent[1];
    recent[1] = recent[2];
    recent[2] = now;
}

static void verifyDisplay(void) {
    if (!vd) {
        return;
    }
    // 刚建好的头几秒不判断
    if (CFAbsoluteTimeGetCurrent() - createdAt < 3) {
        displayScheduleVerify();
        return;
    }
    if (displayOnline(vd.displayID)) {
        enforceTopology();
        return;
    }
    vd = nil;
    mirrored = NO; // 恢复标记和快照留着，重建或放弃时还要用
    if (onDisplayEvent) {
        onDisplayEvent(YES);
    }
}

static void reconfigured(CGDirectDisplayID d, CGDisplayChangeSummaryFlags f, void *u) {
    if (f & kCGDisplayBeginConfigurationFlag) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        displayScheduleVerify();
    });
}

// 屏幕先淡出到黑，建虚拟屏、设镜像、恢复分辨率这几次显示器重新配置都藏在黑屏里，再淡入，看起来只切一次。
// 预约 5 秒，期间出了岔子没淡入，到时系统也会自己恢复
static CGDisplayFadeReservationToken fadeToken;

static void fadeOut(void) {
    if (fadeToken || CGAcquireDisplayFadeReservation(5, &fadeToken) != kCGErrorSuccess) {
        return;
    }
    CGDisplayFade(fadeToken, 0.2, kCGDisplayBlendNormal, kCGDisplayBlendSolidColor, 0, 0, 0, true);
}

// delay 秒后淡入。用运行循环的定时器，理由同 scheduleFinishOff
static void fadeInAfter(double delay) {
    if (!fadeToken) {
        return;
    }
    NSTimer *t = [NSTimer timerWithTimeInterval:delay
                                        repeats:NO
                                          block:^(NSTimer *x) {
                                              if (!fadeToken) {
                                                  return;
                                              }
                                              CGDisplayFade(fadeToken, 0.3, kCGDisplayBlendSolidColor,
                                                            kCGDisplayBlendNormal, 0, 0, 0, true);
                                              CGReleaseDisplayFadeReservation(fadeToken);
                                              fadeToken = 0;
                                          }];
    [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
}

BOOL displayOn(int w, int h, SizeRange r) {
    if (preview) {
        previewOn = YES;
        return YES;
    }
    if (vd) {
        return YES;
    }
    if (closing) {
        return NO;
    }
    curRange = r;
    // 私有类按名字取，系统哪天移除了就走「创建失败」，不至于启动不了
    Class D = NSClassFromString(@"CGVirtualDisplayDescriptor"), V = NSClassFromString(@"CGVirtualDisplay");
    CGVirtualDisplaySettings *st = settingsFor(w, h, 0, 0);
    if (!D || !V || !st) {
        return NO;
    }
    curW = w;
    curH = h;
    // 开启前拍一份各屏的模式，查不到用户配置时用。虚拟屏丢了重建时沿用第一次拍的
    if (!snapshot) {
        snapshot = [NSMutableDictionary dictionary];
        uint32_t n = 0;
        CGDirectDisplayID ids[16];
        if (CGGetOnlineDisplayList(16, ids, &n) == kCGErrorSuccess) {
            for (uint32_t i = 0; i < n; i++) {
                CGDisplayModeRef m = CGDisplayCopyDisplayMode(ids[i]);
                if (m) {
                    snapshot[@(ids[i])] = CFBridgingRelease(m);
                }
            }
        }
    }
    CGVirtualDisplayDescriptor *d = [D new];
    d.queue = dispatch_get_main_queue();
    d.name = L(@"远程模式");
    d.maxPixelsWide = WMAX * 2;
    d.maxPixelsHigh = HMAX * 2;
    d.sizeInMillimeters = CGSizeMake(300, 300);
    d.serialNum = 0x11;
    d.productID = 0x1111;
    d.vendorID = 0xEEEE;
    d.terminationHandler = ^(id a, id b) {
        dispatch_async(dispatch_get_main_queue(), ^{
            displayScheduleVerify();
        });
    };
    fadeOut();
    vd = [(CGVirtualDisplay *)[V alloc] initWithDescriptor:d];
    if (!vd || ![vd applySettings:st]) {
        vd = nil;
        fadeInAfter(0);
        return NO;
    }
    static BOOL registered;
    if (!registered) {
        registered = YES;
        CGDisplayRegisterReconfigurationCallback(reconfigured, NULL);
    }
    mirrored = NO;
    createdAt = CFAbsoluteTimeGetCurrent();
    unsigned g = ++gen;
    CGDirectDisplayID vid = vd.displayID;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (!vd || g != gen || vd.displayID != vid) {
            fadeInAfter(0);
            return;
        }
        applyTopology(vid);
        mirrored = YES;
        fadeInAfter(0.4);
        if (onDisplayEvent) {
            onDisplayEvent(NO);
        }
    });
    return YES;
}

// 把虚拟屏切到设定的那档。档位里没有返回 NO
static BOOL switchToWanted(CGDirectDisplayID vid) {
    if (vdModeOK(vid)) {
        return YES;
    }
    BOOL ok = NO;
    CFArrayRef a = allModes(vid);
    for (CFIndex i = 0; a && i < CFArrayGetCount(a); i++) {
        CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(a, i);
        if (isWanted(m)) {
            CGDisplayConfigRef c;
            if (CGBeginDisplayConfiguration(&c) == kCGErrorSuccess) {
                CGConfigureDisplayWithDisplayMode(c, vid, m, NULL);
                ok = CGCompleteDisplayConfiguration(c, kCGConfigureForSession) == kCGErrorSuccess;
            }
            break;
        }
    }
    if (a) {
        CFRelease(a);
    }
    return ok;
}

void displayResize(int w, int h, SizeRange r) {
    curW = w;
    curH = h;
    curRange = r;
    if (!vd) {
        return;
    }
    CGDirectDisplayID vid = vd.displayID;
    if (switchToWanted(vid)) {
        return;
    }
    // 档位里没有（调过画面高度、换了设备，比例变了）：按新比例重新定义一组。
    // 不销毁重建：远程软件截的是这块屏，换一块它会停在旧画面上。当前这档排第一个，虚拟屏先不动，稍后再切过去
    CGDisplayModeRef cur = CGDisplayCopyDisplayMode(vid);
    int cw = cur ? (int)CGDisplayModeGetWidth(cur) : 0, ch = cur ? (int)CGDisplayModeGetHeight(cur) : 0;
    if (cur) {
        CGDisplayModeRelease(cur);
    }
    CGVirtualDisplaySettings *s = settingsFor(w, h, cw, ch);
    if (!s || ![vd applySettings:s]) {
        return;
    }
    unsigned g = gen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (vd && g == gen && vd.displayID == vid) {
            switchToWanted(vid);
        }
    });
}

// 解除镜像并销毁虚拟屏
static CGDirectDisplayID droppedID; // 刚销毁的虚拟屏的编号，用来确认它真的下线了
static CFAbsoluteTime droppedAt;

static void dropVirtual(void) {
    CGDirectDisplayID p[16];
    uint32_t n = physicals(vd.displayID, p);
    CGDisplayConfigRef c;
    CGBeginDisplayConfiguration(&c);
    for (uint32_t i = 0; i < n; i++) {
        CGConfigureDisplayMirrorOfDisplay(c, p[i], kCGNullDirectDisplay);
    }
    CGCompleteDisplayConfiguration(c, kCGConfigureForSession);
    @autoreleasepool {
        droppedID = vd.displayID;
        vd = nil;
    }
    droppedAt = CFAbsoluteTimeGetCurrent();
    mirrored = NO;
}

// 关闭的后半段：虚拟屏下线之后才恢复。恢复得太早，虚拟屏随后消失时系统会再重排一次，把恢复的模式冲掉。
// 用运行循环的定时器等待，不用主队列的 dispatch_after：退出流程可能是从主队列的块里发起的，
// 那个块没返回之前主队列不会再执行别的块，恢复就永远等不到
static void scheduleFinishOff(double delay) {
    NSTimer *t = [NSTimer timerWithTimeInterval:delay
                                        repeats:NO
                                          block:^(NSTimer *x) {
                                              if (!closing) {
                                                  return;
                                              }
                                              // 还没下线就再等等，最多等到销毁后 8
                                              // 秒。物理屏睡着时系统不会处理显示器变化，等也没用，直接往下走
                                              BOOL waiting = displayOnline(droppedID) &&
                                                             !CGDisplayIsAsleep(CGMainDisplayID()) &&
                                                             CFAbsoluteTimeGetCurrent() - droppedAt < 8;
                                              if (waiting) {
                                                  scheduleFinishOff(0.25);
                                                  return;
                                              }
                                              restoreDisplays();
                                              fadeInAfter(0.4);
                                              closing = NO;
                                              NSArray *w = [offWaiters copy];
                                              [offWaiters removeAllObjects];
                                              for (void (^b)(void) in w) {
                                                  b();
                                              }
                                          }];
    [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
}

// 关闭：解除镜像后等虚拟屏下线再恢复各物理屏，等待期间不占主线程；全部做完后调用 done
void displayOff(void (^done)(void)) {
    if (preview) {
        previewOn = NO;
        if (done) {
            done();
        }
        return;
    }
    if (!vd && !closing) {
        if (done) {
            done();
        }
        return;
    }
    if (!offWaiters) {
        offWaiters = [NSMutableArray array];
    }
    if (done) {
        [offWaiters addObject:[done copy]];
    }
    if (closing) {
        return;
    }
    fadeOut();
    dropVirtual();
    closing = YES;
    scheduleFinishOff(1.5);
}

// 兜底的同步关闭：退出流程没等到异步恢复完成时用
void displayOffSync(void) {
    if (preview) {
        return;
    }
    if (!vd && !closing) {
        return;
    }
    if (vd) {
        dropVirtual();
    }
    usleep(1500000);
    restoreDisplays();
    closing = NO;
}

// 虚拟屏丢失后不再重建：只把物理屏恢复原样
void displayAbandon(void) {
    if (preview) {
        return;
    }
    if (!vd && !closing) {
        restoreDisplays();
    }
}

BOOL displayIsPreview(void) {
    return preview;
}

BOOL displayIsOn(void) {
    return preview ? previewOn : vd != nil;
}

BOOL displayIsMirrored(void) {
    return preview ? previewOn : mirrored;
}

BOOL displayIsClosing(void) {
    return closing;
}

void displaySetEventHandler(void (^handler)(BOOL lost)) {
    onDisplayEvent = [handler copy];
}
