// 物理尺寸（毫米）由官方分辨率和 ppi 换算；top/bottom 是状态栏和底部手势条高度
// 同尺寸的机型各占一行，方便按自己的型号找
// 推荐尺寸以 Pura X View 实测 980x820 为基准推算：宽度让字在各手机上一样大，
// 高度 = 屏幕高 - 状态栏 - 手势条 - 输入法和远程工具栏（约 57mm）
#import <Cocoa/Cocoa.h>

enum { CUT_HOLE, CUT_ISLAND, CUT_NOTCH };

typedef struct {
    const char *group, *name;
    double wmm, hmm, top, bottom;
    int cut, w, h;
    const char *series; // iPhone 按代分组，型号菜单里每代一个子菜单；NULL 表示直接列出
} Model;

extern const Model kModels[];
extern const int kModelCount;
#define NMODEL kModelCount
#define DEFAULT_MODEL 3

// 虚拟屏宽高的总范围和步进（点）。手机、电脑各自的范围见 sizeRange
#define WMIN 600
#define WMAX 2560
#define HMIN 500
#define HMAX 2400
#define STEP 10

typedef struct {
    int wmin, wmax, hmin, hmax;
} SizeRange;

// 电脑模式：用 MacBook 或外接显示器远程控制，画面按那块屏的比例来
BOOL modelIsDesktop(int m);
// 这个设备能调到的宽高范围；m 小于 0 时返回总范围
SizeRange sizeRange(int m);
// 手机全屏时的推荐宽度是半屏的 80%：画面铺满时字要更大一些（Pura X View 实测 980 的 80%）
#define FULL_SCALE 0.8
// 推荐宽度，显示大小的 100%：电脑和手机半屏取表里的 w，手机全屏再乘 FULL_SCALE
int baseW(int m, BOOL full);
// 竖屏：宽度为 w 时，画面占满状态栏以下、手势条以上整块屏幕的高度（不给输入法留位置）。电脑返回推荐高度按 w 等比
int portraitH(int m, int w);

// 按名称找型号，找不到返回 -1
int modelIndexByName(NSString *n);
// 品牌按 kModels 里出现的顺序排
NSArray<NSString *> *groupNames(void);
int groupOfModel(int m);
int firstModelOfGroup(int g);

// 给人看的名字：表里存的是中文原名（也是设置里存的键），英文界面按 en.lproj 翻译。没有中文的（iPhone 型号）原样显示
NSString *shownText(const char *s);
