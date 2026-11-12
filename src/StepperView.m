#import "StepperView.h"
#import "Theme.h"
#import "Tween.h"

// 输入框：开始和结束编辑时让步进器重画焦点环
@interface NumField : NSTextField
@end
@implementation NumField

- (void)mark {
    NSView *v = self.superview;
    dispatch_async(dispatch_get_main_queue(), ^{
        [v setNeedsDisplay:YES];
    });
}

- (BOOL)becomeFirstResponder {
    BOOL r = [super becomeFirstResponder];
    [self mark];
    return r;
}

- (void)textDidEndEditing:(NSNotification *)n {
    [super textDidEndEditing:n];
    [self mark];
}

@end

@implementation StepperView {
    Tween *_hv[2];
    int _hover, _press;
    NSTimer *_timer;
}

- (instancetype)initWithFrame:(NSRect)f {
    self = [super initWithFrame:f];
    NumField *t = [[NumField alloc]
        initWithFrame:NSMakeRect(STEP_ZONE + 2, (f.size.height - 17) / 2, f.size.width - STEP_ZONE * 2 - 4, 17)];
    NSNumberFormatter *nf = [NSNumberFormatter new];
    nf.numberStyle = NSNumberFormatterNoStyle;
    nf.allowsFloats = NO;
    t.formatter = nf;
    t.bordered = NO;
    t.drawsBackground = NO;
    t.focusRingType = NSFocusRingTypeNone;
    t.alignment = NSTextAlignmentCenter;
    t.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightMedium];
    [self addSubview:t];
    self.field = t;
    _canMinus = _canPlus = YES;
    _hv[0] = [[Tween alloc] initWithView:self];
    _hv[1] = [[Tween alloc] initWithView:self];
    return self;
}

- (void)setCanMinus:(BOOL)v {
    if (v != _canMinus) {
        _canMinus = v;
        [self setNeedsDisplay:YES];
    }
}

- (void)setCanPlus:(BOOL)v {
    if (v != _canPlus) {
        _canPlus = v;
        [self setNeedsDisplay:YES];
    }
}

- (int)zoneAt:(NSPoint)p {
    if (!NSPointInRect(p, self.bounds)) {
        return 0;
    }
    return p.x < STEP_ZONE ? -1 : p.x > self.bounds.size.width - STEP_ZONE ? 1 : 0;
}

- (BOOL)can:(int)z {
    return z < 0 ? _canMinus : _canPlus;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    trackHover(self, YES);
}

- (void)setHover:(int)z {
    _hover = z;
    [_hv[0] to:z < 0 ? 1 : 0 over:0.14];
    [_hv[1] to:z > 0 ? 1 : 0 over:0.14];
}

- (void)track:(NSEvent *)e {
    int z = [self zoneAt:[self convertPoint:e.locationInWindow fromView:nil]];
    if (z != _hover) {
        [self setHover:z];
    }
}

- (void)mouseEntered:(NSEvent *)e {
    [self track:e];
}

- (void)mouseMoved:(NSEvent *)e {
    [self track:e];
}

- (void)mouseExited:(NSEvent *)e {
    [self setHover:0];
}

- (void)drawRect:(NSRect)r {
    NSRect b = self.bounds;
    CGFloat W = b.size.width, H = b.size.height;
    [Track() setFill];
    [RR(b, 8) fill];
    // 两侧按钮：悬停时浮出一块主题色底，符号变主题色；到头了变淡
    for (int i = 0; i < 2; i++) {
        int z = i ? 1 : -1;
        BOOL can = [self can:z];
        double hv = can ? _hv[i].value : 0;
        BOOL pr = can && _press == z;
        NSRect zr = NSInsetRect(NSMakeRect(i ? W - STEP_ZONE : 0, 0, STEP_ZONE, H), 2, 2);
        [ThemeA(pr ? 0.26 : 0.14 * hv) setFill];
        [RR(zr, 6) fill];
        NSColor *base = [NSColor.labelColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        NSColor *fg =
            can ? ([base blendedColorWithFraction:MAX(hv, pr ? 1 : 0) ofColor:ThemeInk()] ?: NSColor.labelColor)
                : NSColor.tertiaryLabelColor;
        DrawImg(Sym(i ? @"plus" : @"minus", 11, NSFontWeightSemibold, fg), NSMakePoint(NSMidX(zr), H / 2), 1);
    }
    // 输入中：中间浮起一块面，套一圈主题色
    if (self.field.currentEditor) {
        NSRect m = NSInsetRect(NSMakeRect(STEP_ZONE, 0, W - STEP_ZONE * 2, H), 0, 2);
        [Surface() setFill];
        [RR(m, 6) fill];
        NSBezierPath *p = RR(NSInsetRect(m, 0.75, 0.75), 5.25);
        p.lineWidth = 1.5;
        [ThemeInk() setStroke];
        [p stroke];
    }
}

- (void)stop {
    [_timer invalidate];
    _timer = nil;
    _press = 0;
    [self setNeedsDisplay:YES];
}

- (void)tick {
    if (_press && [self can:_press]) {
        if (self.onStep) {
            self.onStep(_press);
        }
    } else {
        [self stop];
    }
}

- (void)mouseDown:(NSEvent *)e {
    int z = [self zoneAt:[self convertPoint:e.locationInWindow fromView:nil]];
    if (!z) {
        [self.window makeFirstResponder:self.field];
        return;
    }
    if (![self can:z]) {
        return;
    }
    _press = z;
    [self setNeedsDisplay:YES];
    if (self.onStep) {
        self.onStep(z);
    }
    // 按住 0.4 秒后开始连续步进
    _timer = [[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:0.4]
                                      interval:0.06
                                        target:self
                                      selector:@selector(tick)
                                      userInfo:nil
                                       repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)mouseUp:(NSEvent *)e {
    [self stop];
}

@end
