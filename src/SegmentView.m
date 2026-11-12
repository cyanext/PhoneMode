#import "SegmentView.h"
#import "Theme.h"
#import "Tween.h"

@implementation SegmentView {
    Tween *_pos;
    NSInteger _hover;
    BOOL _has;
}

- (instancetype)initWithFrame:(NSRect)f {
    self = [super initWithFrame:f];
    _hover = -1;
    _pos = [[Tween alloc] initWithView:self];
    return self;
}

- (void)setSelected:(NSInteger)s {
    if (_has && s == _selected) {
        return;
    }
    _selected = s;
    [_pos to:s over:_has ? 0.26 : 0];
    _has = YES;
    [self setNeedsDisplay:YES];
}

- (NSInteger)indexAt:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    if (!NSPointInRect(p, self.bounds) || !self.titles.count) {
        return -1;
    }
    return MIN((NSInteger)self.titles.count - 1, (NSInteger)(p.x / (self.bounds.size.width / self.titles.count)));
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    trackHover(self, YES);
}

- (void)track:(NSEvent *)e {
    NSInteger h = [self indexAt:e];
    if (h != _hover) {
        _hover = h;
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseEntered:(NSEvent *)e {
    [self track:e];
}

- (void)mouseMoved:(NSEvent *)e {
    [self track:e];
}

- (void)mouseExited:(NSEvent *)e {
    _hover = -1;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)r {
    NSRect b = self.bounds;
    NSInteger n = self.titles.count;
    if (!n) {
        return;
    }
    CGFloat sw = b.size.width / n;
    double pos = _pos.value;
    [Track() setFill];
    [RR(b, 8) fill];
    NSRect thumb = NSInsetRect(NSMakeRect(pos * sw, 0, sw, b.size.height), 2, 2);
    [Thumb() setFill];
    [RR(thumb, 6) fill];
    NSColor *idle = [(_hover >= 0 ? NSColor.labelColor : NSColor.secondaryLabelColor)
        colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    NSColor *rest = [NSColor.secondaryLabelColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    for (NSInteger i = 0; i < n; i++) {
        double cover = MAX(0, 1 - fabs(pos - i)); // 滑块盖住这一格的程度
        NSColor *base = (i == _hover) ? idle : rest;
        NSColor *fg = [base blendedColorWithFraction:cover
                                             ofColor:[ThemeInk() colorUsingColorSpace:NSColorSpace.sRGBColorSpace]]
                          ?: NSColor.labelColor;
        NSDictionary *a = @{
            NSFontAttributeName : [NSFont systemFontOfSize:13 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName : fg
        };
        NSSize ts = [self.titles[i] sizeWithAttributes:a];
        [self.titles[i]
               drawAtPoint:NSMakePoint(floor(i * sw + (sw - ts.width) / 2), floor((b.size.height - ts.height) / 2))
            withAttributes:a];
    }
}

- (void)mouseDown:(NSEvent *)e {
    NSInteger i = [self indexAt:e];
    if (i >= 0 && i != self.selected && self.onPick) {
        self.onPick(i);
    }
}

@end
