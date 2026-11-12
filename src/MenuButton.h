#import "Flipped.h"
#import <Cocoa/Cocoa.h>

// 右对齐的当前值加上下箭头，点击弹出菜单（手机型号用）
@interface MenuButton : Flipped
@property(copy, nonatomic) NSString *title;
@property(strong) NSMenu *list;
@property NSInteger selectedTag;
- (CGFloat)fitWidthMax:(CGFloat)mx;
@end
