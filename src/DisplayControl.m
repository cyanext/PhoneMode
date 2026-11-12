#import "DisplayControl.h"
#import "CGVirtualDisplay.h"
#import "PhoneModels.h"

static CGVirtualDisplay *vd;              // 当前虚拟屏；nil 表示没开
static CGDirectDisplayID phys;            // 镜像虚拟屏的那块物理屏
static CGDisplayModeRef physMode;         // 物理屏原来的模式，关闭时恢复
static BOOL mirrored;                     // 镜像已经设好
static BOOL closing;                      // 正在关闭：镜像已解除，等着恢复原模式
static unsigned gen;                      // 每建一次虚拟屏加一，用来识别过期的延迟回调
static CFAbsoluteTime createdAt;          // 最近一次建虚拟屏的时间
static NSMutableArray *offWaiters;        // 等关闭完成的回调
static void (^onDisplayEvent)(BOOL lost); // 通知界面刷新；lost 表示虚拟屏被系统回收了
// 开启时把物理屏原模式记进设置，正常恢复后清掉；启动时发现还在，说明上次被强杀或崩溃
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
    if (!physMode) {
        return;
    }
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:@{
        @"display" : @(phys),
        @"w" : @(CGDisplayModeGetWidth(physMode)),
        @"h" : @(CGDisplayModeGetHeight(physMode)),
        @"pw" : @(CGDisplayModeGetPixelWidth(physMode)),
        @"hz" : @(CGDisplayModeGetRefreshRate(physMode))
    }
           forKey:RESTORE_KEY];
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
    NSDictionary *r = [[NSUserDefaults standardUserDefaults] dictionaryForKey:RESTORE_KEY];
    if (!r) {
        return NO;
    }
    BOOL did = NO;
    if ([r[@"w"] respondsToSelector:@selector(intValue)] && [r[@"h"] respondsToSelector:@selector(intValue)] &&
        [r[@"w"] intValue] > 0 && [r[@"h"] intValue] > 0) {
        CGDirectDisplayID d =
            [r[@"display"] respondsToSelector:@selector(unsignedIntValue)] ? [r[@"display"] unsignedIntValue] : 0;
        if (!d || !displayOnline(d)) {
            d = CGMainDisplayID();
        }
        CGDisplayModeRef cur = CGDisplayCopyDisplayMode(d);
        size_t W = [r[@"w"] intValue], H = [r[@"h"] intValue], PW = [r[@"pw"] intValue];
        double R = [r[@"hz"] doubleValue];
        BOOL same = cur && CGDisplayModeGetWidth(cur) == W && CGDisplayModeGetHeight(cur) == H &&
                    CGDisplayModeGetPixelWidth(cur) == PW;
        if (cur) {
            CGDisplayModeRelease(cur);
        }
        if (!same) {
            did = applyMode(d, W, H, PW, R);
        }
    }
    clearRestoreRecord();
    return did;
}

// 只放一档模式，远程软件无法自行改成别的尺寸
static CGVirtualDisplaySettings *settingsFor(int w, int h) {
    CGVirtualDisplaySettings *s = [NSClassFromString(@"CGVirtualDisplaySettings") new];
    s.hiDPI = 1;
    CGVirtualDisplayMode *m =
        [(CGVirtualDisplayMode *)[NSClassFromString(@"CGVirtualDisplayMode") alloc] initWithWidth:w
                                                                                           height:h
                                                                                      refreshRate:60];
    if (!s || !m) {
        return nil;
    }
    s.modes = @[ m ];
    return s;
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
        return;
    }
    vd = nil;
    mirrored = NO; // physMode 和恢复记录留着，重建或放弃时还要用
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
    CGVirtualDisplaySettings *st = settingsFor(w, h);
    if (!D || !V || !st) {
        return NO;
    }
    BOOL fresh = !physMode; // 虚拟屏丢失后重建时，沿用之前记下的物理屏和原模式
    if (fresh) {
        phys = CGMainDisplayID();
        physMode = CGDisplayCopyDisplayMode(phys);
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
    vd = [(CGVirtualDisplay *)[V alloc] initWithDescriptor:d];
    if (!vd || ![vd applySettings:st]) {
        vd = nil;
        if (fresh && physMode) {
            CGDisplayModeRelease(physMode);
            physMode = NULL;
        }
        return NO;
    }
    if (fresh) {
        writeRestoreRecord();
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (!vd || g != gen || vd.displayID != vid) {
            return;
        }
        CGDisplayConfigRef c;
        CGBeginDisplayConfiguration(&c);
        CGConfigureDisplayOrigin(c, vid, 0, 0);
        CGConfigureDisplayMirrorOfDisplay(c, phys, vid);
        CGCompleteDisplayConfiguration(c, kCGConfigureForSession);
        mirrored = YES;
        if (onDisplayEvent) {
            onDisplayEvent(NO);
        }
    });
    return YES;
}

void displayResize(int w, int h) {
    if (vd) {
        CGVirtualDisplaySettings *s = settingsFor(w, h);
        if (s) {
            [vd applySettings:s];
        }
    }
}

// 解除镜像并销毁虚拟屏
static CGDirectDisplayID droppedID; // 刚销毁的虚拟屏的编号，用来确认它真的下线了
static CFAbsoluteTime droppedAt;

static void dropVirtual(void) {
    CGDisplayConfigRef c;
    CGBeginDisplayConfiguration(&c);
    CGConfigureDisplayMirrorOfDisplay(c, phys, kCGNullDirectDisplay);
    CGCompleteDisplayConfiguration(c, kCGConfigureForSession);
    @autoreleasepool {
        droppedID = vd.displayID;
        vd = nil;
    }
    droppedAt = CFAbsoluteTimeGetCurrent();
    mirrored = NO;
}

// 物理屏切回原模式，并清掉恢复记录
static void restorePhysMode(void) {
    if (physMode) {
        applyMode(phys, CGDisplayModeGetWidth(physMode), CGDisplayModeGetHeight(physMode),
                  CGDisplayModeGetPixelWidth(physMode), CGDisplayModeGetRefreshRate(physMode));
        CGDisplayModeRelease(physMode);
        physMode = NULL;
    }
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
                                              BOOL waiting = displayOnline(droppedID) && !CGDisplayIsAsleep(phys) &&
                                                             CFAbsoluteTimeGetCurrent() - droppedAt < 8;
                                              if (waiting) {
                                                  scheduleFinishOff(0.25);
                                                  return;
                                              }
                                              restorePhysMode();
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
