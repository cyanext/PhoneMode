#import "ScrollSpeed.h"
#include <libproc.h>

static CFMachPortRef tap;
static double factor = 1;
// 整数位移缩小后不足 1 的部分攒着，下次补上，慢慢滑也能动
static double restPt1, restPt2, restLine1, restLine2;

static BOOL fromUU(CGEventRef e) {
    static pid_t lastPid;
    static BOOL lastIs;
    pid_t pid = (pid_t)CGEventGetIntegerValueField(e, kCGEventSourceUnixProcessID);
    if (pid != lastPid) {
        char name[256] = "";
        proc_name(pid, name, sizeof name);
        lastPid = pid;
        lastIs = strncmp(name, "UURemote", 8) == 0;
    }
    return lastIs;
}

static int64_t take(double v, double *rest) {
    *rest += v;
    int64_t n = (int64_t)trunc(*rest);
    *rest -= n;
    return n;
}

static CGEventRef onEvent(CGEventTapProxy p, CGEventType t, CGEventRef e, void *u) {
    // 回调太慢或用户操作时系统会停掉拦截，重新打开
    if (t == kCGEventTapDisabledByTimeout || t == kCGEventTapDisabledByUserInput) {
        if (tap) {
            CGEventTapEnable(tap, true);
        }
        return e;
    }
    if (t != kCGEventScrollWheel || factor == 1 || !fromUU(e)) {
        return e;
    }
    double l1 = CGEventGetIntegerValueField(e, kCGScrollWheelEventDeltaAxis1);
    double l2 = CGEventGetIntegerValueField(e, kCGScrollWheelEventDeltaAxis2);
    double p1 = CGEventGetIntegerValueField(e, kCGScrollWheelEventPointDeltaAxis1);
    double p2 = CGEventGetIntegerValueField(e, kCGScrollWheelEventPointDeltaAxis2);
    double f1 = CGEventGetDoubleValueField(e, kCGScrollWheelEventFixedPtDeltaAxis1);
    double f2 = CGEventGetDoubleValueField(e, kCGScrollWheelEventFixedPtDeltaAxis2);
    // 先写行数：写行数会把像素位移一起重算，所以像素和小数位移放在后面写
    CGEventSetIntegerValueField(e, kCGScrollWheelEventDeltaAxis1, take(l1 * factor, &restLine1));
    CGEventSetIntegerValueField(e, kCGScrollWheelEventDeltaAxis2, take(l2 * factor, &restLine2));
    CGEventSetIntegerValueField(e, kCGScrollWheelEventPointDeltaAxis1, take(p1 * factor, &restPt1));
    CGEventSetIntegerValueField(e, kCGScrollWheelEventPointDeltaAxis2, take(p2 * factor, &restPt2));
    CGEventSetDoubleValueField(e, kCGScrollWheelEventFixedPtDeltaAxis1, f1 * factor);
    CGEventSetDoubleValueField(e, kCGScrollWheelEventFixedPtDeltaAxis2, f2 * factor);
    return e;
}

BOOL scrollSpeedSet(double f) {
    factor = f;
    restPt1 = restPt2 = restLine1 = restLine2 = 0;
    if (f == 1) {
        if (tap) {
            CGEventTapEnable(tap, false);
        }
        return YES;
    }
    if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef) @{(__bridge id)kAXTrustedCheckOptionPrompt : @YES})) {
        // 等用户在系统设置里打勾：每秒看一次，授权了就接着开，最多等 5 分钟
        static NSTimer *wait;
        [wait invalidate];
        __block int left = 300;
        wait = [NSTimer scheduledTimerWithTimeInterval:1
                                               repeats:YES
                                                 block:^(NSTimer *t) {
                                                     if (AXIsProcessTrusted()) {
                                                         [t invalidate];
                                                         scrollSpeedSet(factor);
                                                     } else if (--left <= 0 || factor == 1) {
                                                         [t invalidate];
                                                     }
                                                 }];
        return NO;
    }
    if (!tap) {
        // 放在最下游：Mos 这类平滑滚动工具会把 UU 的一下滚动拆成几十个事件重新发出（来源进程不变），
        // 在它前面缩小没用，它按自己的步长放大
        tap = CGEventTapCreate(kCGAnnotatedSessionEventTap, kCGTailAppendEventTap, kCGEventTapOptionDefault,
                               CGEventMaskBit(kCGEventScrollWheel), onEvent, NULL);
        if (!tap) {
            return NO;
        }
        CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), src, kCFRunLoopCommonModes);
        CFRelease(src);
    }
    CGEventTapEnable(tap, true);
    return YES;
}
