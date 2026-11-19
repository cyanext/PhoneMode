// 面板里的两种行：整行可点的 ClickRow，和可以原地改名的预设行 PresetRow
#import <Cocoa/Cocoa.h>

// 整行响应点击（松开在行内才算），不可用时整行变淡。内容由外面往里加，坐标原点在左上角。
// 鼠标停上去和菜单选中一样：铺一块强调色圆角底，上面的文字、图标变白
@interface ClickRow : NSView
@property(copy) void (^onClick)(void);
@property(nonatomic) BOOL enabled;
// 面板收起时调：鼠标没移出就收起，系统不会再发移出事件
- (void)clearHover;
@end

// 一条预设：勾、名字、尺寸。单击切换；双击或 beginRename 原地改名：
// 回车或点输入框以外确认，Esc 放弃，名字留空等于不改。右键弹 menu
@interface PresetRow : NSView <NSTextFieldDelegate>
- (instancetype)initWithFrame:(NSRect)f name:(NSString *)name detail:(NSString *)detail;
@property(nonatomic) BOOL checked;
@property(copy) void (^onPick)(void);
@property(copy) void (^onRename)(NSString *name);
- (void)beginRename;
- (void)clearHover;
@end

// 点在正在编辑的输入框以外（同一窗口里）就结束编辑。程序启动时调一次
void endEditingOnOutsideClick(void);
