#import "Tween.h"

@implementation Tween {
    __weak NSView *_view;
    double _from, _to, _dur;
    CFAbsoluteTime _t0;
    NSTimer *_timer;
}

- (instancetype)initWithView:(NSView *)v {
    self = [super init];
    _view = v;
    return self;
}

- (double)value {
    if (!_timer) {
        return _to;
    }
    double t = (CFAbsoluteTimeGetCurrent() - _t0) / _dur;
    if (t >= 1) {
        return _to;
    }
    t = 1 - pow(1 - t, 3);
    return _from + (_to - _from) * t;
}

- (void)to:(double)target over:(double)sec {
    if (target == _to) {
        return;
    }
    if (sec <= 0 || !_view.window.visible) {
        _to = target;
        [_timer invalidate];
        _timer = nil;
    } else {
        _from = self.value;
        _to = target;
        _dur = sec;
        _t0 = CFAbsoluteTimeGetCurrent();
        if (!_timer) {
            _timer = [NSTimer timerWithTimeInterval:1 / 60.0
                                             target:self
                                           selector:@selector(tick)
                                           userInfo:nil
                                            repeats:YES];
            [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
        }
    }
    [_view setNeedsDisplay:YES];
}

- (void)tick {
    if (!_view || CFAbsoluteTimeGetCurrent() - _t0 >= _dur) {
        [_timer invalidate];
        _timer = nil;
    }
    [_view setNeedsDisplay:YES];
}

@end
