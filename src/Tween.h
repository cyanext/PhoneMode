#import <Cocoa/Cocoa.h>

// 一个会缓动的数值：悬停、按下、开关、滑块位置都用它，变化时让所属视图重画
@interface Tween : NSObject
@property(readonly) double value;
- (instancetype)initWithView:(NSView *)v;
- (void)to:(double)target over:(double)sec;
@end
