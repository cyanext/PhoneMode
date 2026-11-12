#import "Flipped.h"
#import <Cocoa/Cocoa.h>

// 分组卡片：圆角面，靠底色与窗口区分；行间一条很淡的分隔线，从文字左缘起
@interface Card : Flipped
@property int rows;
@property CGFloat rowH;
@end
