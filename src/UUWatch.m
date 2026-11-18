#import "UUWatch.h"

#define POLL 0.5       // 检查间隔（秒）
#define GONE_POLLS 12  // 提示框连续消失这么多次才算断开：开启远程画面、调尺寸时屏幕重新配置，提示框可能一闪而过

static BOOL overlayShown(void) {
    NSArray *ws = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
    for (NSDictionary *w in ws) {
        NSString *owner = w[(id)kCGWindowOwnerName];
        if ([owner hasPrefix:@"UURemote"] && [w[(id)kCGWindowLayer] intValue] >= CGShieldingWindowLevel() - 1) {
            return YES;
        }
    }
    return NO;
}

static BOOL connected;

BOOL uuWatchConnected(void) {
    return connected;
}

void uuWatchStart(void (^changed)(BOOL connected)) {
    static NSTimer *timer;
    static int gone;
    [timer invalidate];
    void (^cb)(BOOL) = [changed copy];
    timer = [NSTimer scheduledTimerWithTimeInterval:POLL
                                            repeats:YES
                                              block:^(NSTimer *t) {
                                                  BOOL shown = overlayShown();
                                                  gone = shown ? 0 : gone + 1;
                                                  BOOL now = shown || (connected && gone < GONE_POLLS);
                                                  if (now != connected) {
                                                      connected = now;
                                                      cb(now);
                                                  }
                                              }];
    timer.tolerance = 0.3;
}
