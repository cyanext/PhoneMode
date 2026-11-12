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

// 虚拟屏宽高的允许范围和步进（点）
#define WMIN 800
#define WMAX 1400
#define HMIN 500
#define HMAX 1600
#define STEP 10

// 按名称找型号，找不到返回 -1
int modelIndexByName(NSString *n);
// 品牌按 kModels 里出现的顺序排
NSArray<NSString *> *groupNames(void);
int groupOfModel(int m);
int firstModelOfGroup(int g);
