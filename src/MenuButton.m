#import "MenuButton.h"
#import "Theme.h"
#import "Tween.h"

@implementation MenuButton {
    Tween *_hoverT;
    BOOL _pressed;
}

- (instancetype)initWithFrame:(NSRect)f {
    self = [super initWithFrame:f];
    _hoverT = [[Tween alloc] initWithView:self];
    return self;
}

- (NSDictionary *)attrs {
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.lineBreakMode = NSLineBreakByTruncatingTail;
    ps.alignment = NSTextAlignmentRight;
    return @{
        NSFontAttributeName : [NSFont systemFontOfSize:13 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName : NSColor.labelColor,
        NSParagraphStyleAttributeName : ps
    };
}

- (void)setTitle:(NSString *)t {
    _title = [t copy];
    [self setNeedsDisplay:YES];
}

- (CGFloat)fitWidthMax:(CGFloat)mx {
    return MIN(mx, ceil([self.title sizeWithAttributes:[self attrs]].width) + 8 + 24);
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
    NSRect b = self.bounds;
    double hv = _hoverT.value;
    [ThemeA(_pressed ? 0.24 : 0.13 * hv) setFill];
    [RR(b, 8) fill];
    NSDictionary *a = [self attrs];
    CGFloat th = [self.title sizeWithAttributes:a].height;
    [self.title drawInRect:NSMakeRect(8, floor((b.size.height - th) / 2), b.size.width - 8 - 24, th) withAttributes:a];
    NSColor *base = [NSColor.secondaryLabelColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    DrawImg(Sym(@"chevron.up.chevron.down", 10, NSFontWeightSemibold,
                [base blendedColorWithFraction:MAX(hv, _pressed ? 1 : 0) ofColor:ThemeInk()]
                    ?: NSColor.secondaryLabelColor),
            NSMakePoint(b.size.width - 13, b.size.height / 2), 1);
}

- (void)mouseDown:(NSEvent *)e {
    _pressed = YES;
    [self display];
    CGFloat mw = self.list.size.width;
    [self.list popUpMenuPositioningItem:[self.list itemWithTag:self.selectedTag]
                             atLocation:NSMakePoint(self.bounds.size.width - mw + 8, 4)
                                 inView:self];
    _pressed = NO;
    BOOL in =
        NSPointInRect([self convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil], self.bounds);
    [_hoverT to:in ? 1 : 0 over:0.2];
    [self setNeedsDisplay:YES];
}

@end
