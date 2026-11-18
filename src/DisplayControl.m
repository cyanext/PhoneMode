#import "DisplayControl.h"
#import "CGVirtualDisplay.h"
#import "PhoneModels.h"

static CGVirtualDisplay *vd;              // 当前虚拟屏；nil 表示没开
static NSMutableDictionary *origModes;    // 显示器编号 -> 镜像前的原模式（CGDisplayModeRef），关闭时恢复
// 显示器编号 -> 建虚拟屏之前的模式。虚拟屏一接上，系统可能先把物理屏从缩放的 HiDPI 模式切到原生分辨率，
// 等到镜像时再记就记成了被改过的模式，所以建之前先拍一份
static NSMutableDictionary *preModes;
static BOOL mirrored;                     // 镜像已经设好
static BOOL closing;                      // 正在关闭：镜像已解除，等着恢复原模式
static unsigned gen;                      // 每建一次虚拟屏加一，用来识别过期的延迟回调
static CFAbsoluteTime createdAt;          // 最近一次建虚拟屏的时间
static NSMutableArray *offWaiters;        // 等关闭完成的回调
static void (^onDisplayEvent)(BOOL lost); // 通知界面刷新；lost 表示虚拟屏被系统回收了
static int curW, curH;                    // 虚拟屏应有的尺寸，修复分辨率时用
// 镜像物理屏时把它们的原模式记进设置，正常恢复后清掉；启动时发现还在，说明上次被强杀或崩溃
#define RESTORE_KEY @"restore"
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

// 把显示器切到指定的模式（点数宽高、像素宽、刷新率都对上才算）
static BOOL applyMode(CGDirectDisplayID d, size_t W, size_t H, size_t PW, double R) {
    BOOL ok = NO;
    CFArrayRef a = allModes(d);
    if (!a) {
        return NO;
    }
    for (CFIndex i = 0; i < CFArrayGetCount(a); i++) {
        CGDisplayModeRef m = (CGDisplayModeRef)CFArrayGetValueAtIndex(a, i);
        if (CGDisplayModeGetWidth(m) == W && CGDisplayModeGetHeight(m) == H && CGDisplayModeGetPixelWidth(m) == PW &&
            fabs(CGDisplayModeGetRefreshRate(m) - R) < 1) {
            CGDisplayConfigRef c;
            CGBeginDisplayConfiguration(&c);
            CGConfigureDisplayWithDisplayMode(c, d, m, NULL);
            ok = CGCompleteDisplayConfiguration(c, kCGConfigurePermanently) == kCGErrorSuccess;
            break;
        }
    }
    CFRelease(a);
    return ok;
}

static void writeRestoreRecord(void) {
    NSMutableArray *a = [NSMutableArray array];
    for (NSNumber *k in origModes) {
        CGDisplayModeRef m = (__bridge CGDisplayModeRef)origModes[k];
        [a addObject:@{
            @"display" : k,
            @"w" : @(CGDisplayModeGetWidth(m)),
            @"h" : @(CGDisplayModeGetHeight(m)),
            @"pw" : @(CGDisplayModeGetPixelWidth(m)),
            @"hz" : @(CGDisplayModeGetRefreshRate(m))
        }];
    }
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:a forKey:RESTORE_KEY];
    [ud synchronize]; // 立刻落盘，随后被强杀也还在
}

static void clearRestoreRecord(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:RESTORE_KEY]) {
        [ud removeObjectForKey:RESTORE_KEY];
        [ud synchronize];
    }
}

// 启动时调用：上次没正常恢复就先把物理屏切回记录的模式。返回是否做了恢复
BOOL displayRecoverFromCrash(void) {
    if (preview) {
        return NO;
    }
    id r = [[NSUserDefaults standardUserDefaults] objectForKey:RESTORE_KEY];
    NSArray *list = [r isKindOfClass:[NSArray class]] ? r : [r isKindOfClass:[NSDictionary class]] ? @[ r ] : nil;
    BOOL did = NO;
    for (NSDictionary *e in list) {
        if (![e isKindOfClass:[NSDictionary class]] || [e[@"w"] intValue] <= 0 || [e[@"h"] intValue] <= 0) {
            continue;
        }
        CGDirectDisplayID d = [e[@"display"] unsignedIntValue];
        if (!d || !displayOnline(d)) {
            if (list.count > 1) {
                continue; // 多块屏时对不上号就跳过，免得把别的屏改错
            }
            d = CGMainDisplayID(); // 只有一块时，重启后编号可能变了，按主屏处理
        }
        CGDisplayModeRef cur = CGDisplayCopyDisplayMode(d);
        size_t W = [e[@"w"] intValue], H = [e[@"h"] intValue], PW = [e[@"pw"] intValue];
        BOOL same = cur && CGDisplayModeGetWidth(cur) == W && CGDisplayModeGetHeight(cur) == H &&
                    CGDisplayModeGetPixelWidth(cur) == PW;
        if (cur) {
            CGDisplayModeRelease(cur);
        }
        if (!same && applyMode(d, W, H, PW, [e[@"hz"] doubleValue])) {
            did = YES;
        }
    }
    clearRestoreRecord();
    return did;
}

// 虚拟屏的一组档位：设定的那档，同比例下宽 WMIN–WMAX，同宽度下高 ±300，都每 STEP 一档。
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
    void (^add)(int, int) = ^(int x, int y) {
        NSString *k = [NSString stringWithFormat:@"%dx%d", x, y];
        if (x < WMIN || x > WMAX || y < HMIN || y > HMAX || [seen containsObject:k]) {
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
    for (int x = w - (w - WMIN) / STEP * STEP; x <= WMAX; x += STEP) {
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

// 设成应有的排列。第一次镜像的物理屏先记下原模式，关闭时恢复
static BOOL applyTopology(CGDirectDisplayID vid) {
    if (!origModes) {
        origModes = [NSMutableDictionary dictionary];
    }
    CGDirectDisplayID p[16];
    uint32_t n = physicals(vid, p);
    BOOL added = NO;
    for (uint32_t i = 0; i < n; i++) {
        if (origModes[@(p[i])]) {
            continue;
        }
        id m = preModes[@(p[i])] ?: CFBridgingRelease(CGDisplayCopyDisplayMode(p[i]));
        if (m) {
            origModes[@(p[i])] = m;
            added = YES;
        }
    }
    if (added) {
        writeRestoreRecord();
    }
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
    mirrored = NO; // 原模式和恢复记录留着，重建或放弃时还要用
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

// 屏幕先淡出到黑，建虚拟屏、设镜像、恢复原模式这几次显示器重新配置都藏在黑屏里，再淡入，看起来只切一次。
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

BOOL displayOn(int w, int h) {
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
    // 私有类按名字取，系统哪天移除了就走「创建失败」，不至于启动不了
    Class D = NSClassFromString(@"CGVirtualDisplayDescriptor"), V = NSClassFromString(@"CGVirtualDisplay");
    CGVirtualDisplaySettings *st = settingsFor(w, h, 0, 0);
    if (!D || !V || !st) {
        return NO;
    }
    curW = w;
    curH = h;
    // 建虚拟屏之前拍下各显示器的模式。已经记过原模式的（虚拟屏丢了重建时）沿用旧的，这里拍到的是镜像中的模式，用不上
    preModes = [NSMutableDictionary dictionary];
    uint32_t n = 0;
    CGDirectDisplayID ids[16];
    if (CGGetOnlineDisplayList(16, ids, &n) == kCGErrorSuccess) {
        for (uint32_t i = 0; i < n; i++) {
            CGDisplayModeRef m = CGDisplayCopyDisplayMode(ids[i]);
            if (m) {
                preModes[@(ids[i])] = CFBridgingRelease(m);
            }
        }
    }
    CGVirtualDisplayDescriptor *d = [D new];
    d.queue = dispatch_get_main_queue();
    d.name = @"远程模式";
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
        applyTopology(vid); // 虚拟屏丢失后重建时，已记下的原模式沿用
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

void displayResize(int w, int h) {
    curW = w;
    curH = h;
    if (!vd) {
        return;
    }
    CGDirectDisplayID vid = vd.displayID;
    if (switchToWanted(vid)) {
        return;
    }
    // 档位里没有（调过画面高度，比例变了）：按新比例重新定义一组。当前这档排第一个，虚拟屏先不动，稍后再切过去
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

// 物理屏切回原模式，并清掉恢复记录。已经拔掉的屏查不到模式，自动跳过
static void restorePhysMode(void) {
    for (NSNumber *k in origModes) {
        CGDisplayModeRef m = (__bridge CGDisplayModeRef)origModes[k];
        applyMode(k.unsignedIntValue, CGDisplayModeGetWidth(m), CGDisplayModeGetHeight(m),
                  CGDisplayModeGetPixelWidth(m), CGDisplayModeGetRefreshRate(m));
    }
    origModes = nil;
    clearRestoreRecord();
}

// 关闭的后半段：虚拟屏下线之后才恢复原模式。恢复得太早，虚拟屏随后消失时系统会再重排一次，把恢复的模式冲掉。
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
                                              restorePhysMode();
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

// 关闭：解除镜像后等 1.5 秒再恢复原模式，等待期间不占主线程；全部做完后调用 done
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
    restorePhysMode();
    closing = NO;
}

// 虚拟屏丢失后不再重建：只把物理屏恢复原样
void displayAbandon(void) {
    if (preview) {
        return;
    }
    if (!vd && !closing) {
        restorePhysMode();
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
