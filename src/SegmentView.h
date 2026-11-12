#import "Flipped.h"
#import <Cocoa/Cocoa.h>

// 品牌用的分段选择：选中的那格是一块比底槽亮的滑块，文字用主题色；切换时滑块滑过去，文字颜色跟着渐变
@interface SegmentView : Flipped
@property(strong, nonatomic) NSArray<NSString *> *titles;
@property(nonatomic) NSInteger selected;
@property(copy) void (^onPick)(NSInteger);
@end
