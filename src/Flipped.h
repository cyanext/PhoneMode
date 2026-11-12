// 坐标原点在左上角的视图，其他控件都从它派生
#import <Cocoa/Cocoa.h>

@interface Flipped : NSView
@end

// 给视图装上悬停跟踪区；moved 为 YES 时还要鼠标移动事件
void trackHover(NSView *v, BOOL moved);
