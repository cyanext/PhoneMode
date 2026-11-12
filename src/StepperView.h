#import "Flipped.h"
#import <Cocoa/Cocoa.h>

// 一体的「− 数值 +」：点一下走一步，按住连续走，中间可以直接输入
#define STEP_ZONE 36
@interface StepperView : Flipped
@property(strong) NSTextField *field;
@property(copy) void (^onStep)(int dir);
@property(nonatomic) BOOL canMinus, canPlus;
@end
