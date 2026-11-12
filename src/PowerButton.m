#import "PowerButton.h"
#import "Theme.h"
#import "Tween.h"

@implementation PowerButton {
    Tween *_onT, *_hoverT, *_pressT;
    BOOL _on, _pressed;
    NSTimer *_pulse;
}

- (instancetype)initWithFrame:(NSRect)f {
    self = [super initWithFrame:f];
    _onT = [[Tween alloc] initWithView:self];
    _hoverT = [[Tween alloc] initWithView:self];
    _pressT = [[Tween alloc] initWithView:self];
    return self;
}

- (BOOL)on {
    return _on;
}

- (void)setOn:(BOOL)on animated:(BOOL)anim {
    _on = on;
    [_onT to:on ? 1 : 0 over:anim ? 0.3 : 0];
}

// 忙的时候（正在关闭）不接受点击，电源符号缓慢明暗
- (void)setBusy:(BOOL)b {
    if (b == _busy) {
        return;
    }
    _busy = b;
    [_pulse invalidate];
    _pulse = nil;
    if (b) {
        _pulse = [NSTimer timerWithTimeInterval:1 / 30.0
                                         target:self
                                       selector:@selector(pulse)
                                       userInfo:nil
                                        repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:_pulse forMode:NSRunLoopCommonModes];
        [_hoverT to:0 over:0.15];
    }
    [self setNeedsDisplay:YES];
}

- (void)pulse {
    [self setNeedsDisplay:YES];
}

- (BOOL)inCircle:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    CGFloat dx = p.x - NSMidX(self.bounds), dy = p.y - NSMidY(self.bounds);
    return dx * dx + dy * dy <= POWER_D * POWER_D / 4.0;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    trackHover(self, YES);
}

- (void)track:(NSEvent *)e {
    [_hoverT to:(!_busy && [self inCircle:e]) ? 1 : 0 over:0.15];
}

- (void)mouseEntered:(NSEvent *)e {
    [self track:e];
}

- (void)mouseMoved:(NSEvent *)e {
    [self track:e];
}

- (void)mouseExited:(NSEvent *)e {
    [_hoverT to:0 over:0.15];
}

- (void)drawRect:(NSRect)r {
    double t = _onT.value, hv = _hoverT.value, pr = _pressT.value;
    BOOL dark = isDark(self);
    NSPoint c = NSMakePoint(NSMidX(self.bounds), NSMidY(self.bounds));
    CGFloat d = POWER_D * (1 - 0.045 * pr);
    NSRect cr = NSMakeRect(c.x - d / 2, c.y - d / 2, d, d);
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:cr];
    CGContextRef cg = NSGraphicsContext.currentContext.CGContext;
    // 开启时外面两圈光晕
    if (t > 0) {
        for (int i = 2; i >= 1; i--) {
            CGFloat g = d + i * 16 * t;
            [ThemeA((i == 1 ? 0.17 : 0.09) * t) setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - g / 2, c.y - g / 2, g, g)] fill];
        }
    }
    // 关闭状态：浅色圆
    if (t < 1) {
        [Surface() setFill];
        [circle fill];
        [ThemeA(0.07 * hv + 0.08 * pr) setFill];
        [circle fill];
    }
    // 开启状态盖在上面，按过渡进度淡入
    if (t > 0) {
        CGContextSaveGState(cg);
        CGContextSetAlpha(cg, t);
        CGContextBeginTransparencyLayer(cg, NULL);
        [[[NSGradient alloc] initWithStartingColor:RGB(0x7F78FF, 1)
                                       endingColor:RGB(0x4E48DC, 1)] drawInBezierPath:circle angle:90];
        [RGB(0xFFFFFF, 0.10 * hv) setFill];
        [circle fill];
        [RGB(0x000000, 0.12 * pr) setFill];
        [circle fill];
        CGContextEndTransparencyLayer(cg);
        CGContextRestoreGState(cg);
    }
    CGFloat pt = d * 0.36, breathe = _busy ? 0.55 + 0.35 * sin(CFAbsoluteTimeGetCurrent() * 4.5) : 1;
    if (t < 1) {
        DrawImg(Sym(@"power", pt, NSFontWeightMedium,
                    [ThemeInk() blendedColorWithFraction:1 - hv
                                                 ofColor:(dark ? RGB(0xFFFFFF, 0.5) : RGB(0x000000, 0.4))]
                        ?: ThemeInk()),
                c, (1 - t) * breathe);
    }
    if (t > 0) {
        DrawImg(Sym(@"power", pt, NSFontWeightMedium, NSColor.whiteColor), c, t);
    }
}

- (void)mouseDown:(NSEvent *)e {
    if (_busy || ![self inCircle:e]) {
        return;
    }
    _pressed = YES;
    [_pressT to:1 over:0.09];
}

- (void)mouseDragged:(NSEvent *)e {
    if (_busy) {
        return;
    }
    BOOL in = [self inCircle:e];
    if (_pressed != in && (_pressed || in)) {
        _pressed = in;
        [_pressT to:in ? 1 : 0 over:0.12];
    }
}

- (void)mouseUp:(NSEvent *)e {
    if (!_pressed) {
        return;
    }
    _pressed = NO;
    [_pressT to:0 over:0.2];
    [NSApp sendAction:self.action to:self.target from:self];
}

// 辅助功能：当成一个按钮
- (BOOL)isAccessibilityElement {
    return YES;
}

- (NSAccessibilityRole)accessibilityRole {
    return NSAccessibilityButtonRole;
}

- (NSString *)accessibilityLabel {
    return self.on ? @"远程画面，已开启" : @"远程画面，已关闭";
}

- (BOOL)accessibilityPerformPress {
    if (_busy) {
        return NO;
    }
    [NSApp sendAction:self.action to:self.target from:self];
    return YES;
}

@end
