#import "Flipped.h"
#import <Cocoa/Cocoa.h>

// 用于预设和「存为预设」。普通：浅底；当前：主题色实心加下拉箭头；添加：无底的主题色文字按钮。悬停时底色渐变到主题色
enum { PB_PLAIN, PB_SELECTED, PB_ADD };

@interface PillButton : Flipped
@property(copy) NSString *title, *symbol, *trailing;
@property int style;
@property BOOL dimmed;
@property NSInteger index;
@property(weak) id target;
@property SEL action;
@property(strong) NSMenu *contextMenu;
- (CGFloat)fitWidth;
- (void)popMenu;
@end
