#import "Flipped.h"
#import <Cocoa/Cocoa.h>

// 远程画面的总开关：开着是主题色的圆加两圈光晕，关着是浅色的圆；状态之间渐变，悬停变亮，按下缩小并压暗
#define POWER_D 104
@interface PowerButton : Flipped
@property(nonatomic, readonly) BOOL on;
@property(nonatomic) BOOL busy;
@property(weak) id target;
@property SEL action;
- (void)setOn:(BOOL)on animated:(BOOL)anim;
@end
