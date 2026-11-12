#import "Flipped.h"

@implementation Flipped

- (BOOL)isFlipped {
    return YES;
}

@end

void trackHover(NSView *v, BOOL moved) {
    for (NSTrackingArea *t in [v.trackingAreas copy]) {
        [v removeTrackingArea:t];
    }
    [v addTrackingArea:[[NSTrackingArea alloc]
                           initWithRect:NSZeroRect
                                options:NSTrackingMouseEnteredAndExited | (moved ? NSTrackingMouseMoved : 0) |
                                        NSTrackingActiveAlways | NSTrackingInVisibleRect
                                  owner:v
                               userInfo:nil]];
}
