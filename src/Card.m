#import "Card.h"
#import "Theme.h"

@implementation Card

- (void)drawRect:(NSRect)r {
    [Surface() setFill];
    [RR(self.bounds, 12) fill];
    [Ink(0.07) setFill];
    for (int i = 1; i < self.rows; i++) {
        NSRectFillUsingOperation(NSMakeRect(48, i * self.rowH, self.bounds.size.width - 48 - 12, 1),
                                 NSCompositingOperationSourceOver);
    }
}

@end
