#import "PillButton.h"
#import "Theme.h"
#import "Tween.h"

@implementation PillButton {
    Tween *_hoverT;
    BOOL _pressed;
}

- (instancetype)initWithFrame:(NSRect)f {
    self = [super initWithFrame:f];
    _hoverT = [[Tween alloc] initWithView:self];
    return self;
}

- (NSDictionary *)attrs:(NSColor *)c {
    return @{
        NSFontAttributeName : [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName : c
    };
}

- (NSImage *)lead:(NSColor *)c {
    return self.symbol ? Sym(self.symbol, 11, NSFontWeightSemibold, c) : nil;
}

- (NSImage *)trail:(NSColor *)c {
    return self.trailing ? Sym(self.trailing, 8, NSFontWeightBold, c) : nil;
}

- (CGFloat)contentWidth {
    CGFloat w = [self.title sizeWithAttributes:[self attrs:NSColor.blackColor]].width;
    NSImage *a = [self lead:nil], *b = [self trail:nil];
    if (a) {
        w += a.size.width + 4;
    }
    if (b) {
        w += b.size.width + 4;
    }
    return ceil(w);
}

- (CGFloat)fitWidth {
    return [self contentWidth] + 24;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    trackHover(self, NO);
}

- (void)mouseEntered:(NSEvent *)e {
    [_hoverT to:1 over:0.14];
}

- (void)mouseExited:(NSEvent *)e {
    [_hoverT to:0 over:0.2];
}

- (void)drawRect:(NSRect)r {
    BOOL live = !self.dimmed;
    double hv = live ? _hoverT.value : 0;
    BOOL pr = _pressed && live;
    NSRect b = self.bounds;
    NSBezierPath *p = RR(b, b.size.height / 2);
    NSColor *fg;
    switch (self.style) {
    case PB_SELECTED:
        [ThemeA(1) setFill];
        [p fill];
        if (pr) {
            [RGB(0x000000, 0.16) setFill];
            [p fill];
        } else {
            [RGB(0xFFFFFF, 0.12 * hv) setFill];
            [p fill];
        }
        fg = NSColor.whiteColor;
        break;
    case PB_ADD:
        [ThemeA(pr ? 0.22 : 0.12 * hv) setFill];
        [p fill];
        fg = ThemeInk();
        break;
    default:
        [Ink(0.06 * (1 - hv)) setFill];
        [p fill];
        [ThemeA(pr ? 0.26 : 0.15 * hv) setFill];
        [p fill];
        fg = NSColor.labelColor;
    }
    NSDictionary *a = [self attrs:fg];
    NSSize ts = [self.title sizeWithAttributes:a];
    NSImage *li = [self lead:fg], *ti = [self trail:fg];
    CGFloat x = floor((b.size.width - [self contentWidth]) / 2), cy = b.size.height / 2;
    if (li) {
        DrawImg(li, NSMakePoint(x + li.size.width / 2, cy), 1);
        x += li.size.width + 4;
    }
    [self.title drawAtPoint:NSMakePoint(x, floor((b.size.height - ts.height) / 2)) withAttributes:a];
    x += ts.width;
    if (ti) {
        DrawImg(ti, NSMakePoint(x + 4 + ti.size.width / 2, cy + 0.5), 0.9);
    }
}

- (void)popMenu {
    if (self.contextMenu) {
        [self.contextMenu popUpMenuPositioningItem:nil
                                        atLocation:NSMakePoint(0, self.bounds.size.height + 4)
                                            inView:self];
    }
}

- (void)mouseDown:(NSEvent *)e {
    if (self.dimmed) {
        return;
    }
    if (e.modifierFlags & NSEventModifierFlagControl) {
        [self popMenu];
        return;
    }
    _pressed = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)e {
    BOOL in = NSPointInRect([self convertPoint:e.locationInWindow fromView:nil], self.bounds);
    if (in != _pressed) {
        _pressed = in;
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseUp:(NSEvent *)e {
    if (!_pressed) {
        return;
    }
    _pressed = NO;
    [self setNeedsDisplay:YES];
    [NSApp sendAction:self.action to:self.target from:self]; // 放在最后：动作里可能把自己移除
}

- (void)rightMouseDown:(NSEvent *)e {
    [self popMenu];
}

@end
