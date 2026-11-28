#import "Localize.h"
#import "AppDelegate.h"
#import "DisplayControl.h"
#import "OtherApps.h"
#import "PhoneModels.h"
#import "Rows.h"
#import "ScrollSpeed.h"
#import "Theme.h"
#import "UUWatch.h"
#import "Updater.h"

// 坐标原点在左上角的容器，从上往下排版方便
@interface FlipView : NSView
@end
@implementation FlipView
- (BOOL)isFlipped {
    return YES;
}
@end

@interface AppDelegate ()
@property(strong) NSStatusItem *statusItem;
@property(strong) NSPopover *popover;
@property(strong) FlipView *root, *presetBox, *phoneRow, *lowerBox;
@property(strong) NSSwitch *power, *followUU;
@property(strong) NSSegmentedControl *fullSeg;
@property(strong) NSTextField *stateLabel, *sizeLabel, *heightLabel;
@property(strong) NSPopUpButton *modelBtn, *scrollBtn;
@property(strong) NSSlider *slider;
@property(strong) NSSegmentedControl *heightSeg;
@property(strong) id<NSObject> activity;
@property(strong) id outsideClick; // 面板打开期间监听别的程序里的鼠标按下，用来收起面板
@property(strong) NSArray<PresetRow *> *presetRows;
@property(strong) ClickRow *addRow, *quitRow, *updateRow;
@end

@implementation AppDelegate {
    int _model, _w, _h, _rebuilds;
    // 宽高比（高 ÷ 宽）。拖显示大小时保持不变；选机型、选预设、调画面高度时重算
    double _ratio;
    BOOL _terminating, _full; // _full：手机画面全屏（铺满）还是半屏（留出输入法）
    CFAbsoluteTime _rebuildT0;
}

#define PANEL_W 320
#define PAD 16
#define ROW_H 44
#define TITLE_X 52 // 行标题的左边距，图标在它左边
#define SIZE_H 90  // 显示大小这一块：标题行、滑块、两端说明
#define PRESET_H 32

#pragma mark 设置存取

- (int)currentW {
    return _w;
}

- (int)currentH {
    return _h;
}

- (NSUserDefaults *)ud {
    return [NSUserDefaults standardUserDefaults];
}

// 读预设时顺手清洗：设置文件被外部改坏（不是字典、缺名称、尺寸不是数字）的条目直接丢掉，尺寸夹到允许范围
- (NSArray *)presets {
    NSMutableArray *out = [NSMutableArray array];
    for (id d in [self.ud arrayForKey:@"presets"] ?: @[]) {
        if (![d isKindOfClass:NSDictionary.class]) {
            continue;
        }
        id name = d[@"name"], model = d[@"model"], w = d[@"w"], h = d[@"h"];
        if (![name isKindOfClass:NSString.class] || ![name length]) {
            continue;
        }
        if (![w respondsToSelector:@selector(intValue)] || ![h respondsToSelector:@selector(intValue)]) {
            continue;
        }
        model = [model isKindOfClass:NSString.class] ? model : @"";
        SizeRange r = sizeRange(modelIndexByName(model));
        [out addObject:@{
            @"name" : name,
            @"model" : model,
            @"w" : @(MAX(r.wmin, MIN(r.wmax, [w intValue]))),
            @"h" : @(MAX(r.hmin, MIN(r.hmax, [h intValue])))
        }];
    }
    return out;
}

- (void)setPresets:(NSArray *)a {
    [self.ud setObject:a forKey:@"presets"];
    [self buildPresets];
}

- (void)load {
    _full = [self.ud objectForKey:@"full"] ? [self.ud boolForKey:@"full"] : YES;
    _model = modelIndexByName([self.ud stringForKey:@"model"] ?: @"");
    if (_model < 0) {
        _model = DEFAULT_MODEL;
    }
    _w = (int)[self.ud integerForKey:@"w"] ?: baseW(_model, _full);
    _h = (int)[self.ud integerForKey:@"h"] ?: [self defaultH:_model w:_w];
    // 从 1.5 及以前升级上来：存的是半屏尺寸，没有全屏半屏的设置。按全屏换算一次，显示大小的比例不变。
    // 1.6、1.6.1 也没在换设备时存这个设置，所以看宽高比更接近哪一种：接近全屏的已经是全屏尺寸，不动
    if (![self.ud objectForKey:@"full"]) {
        [self.ud setBool:YES forKey:@"full"];
        if (!modelIsDesktop(_model)) {
            double r = (double)_h / _w, half = (double)kModels[_model].h / kModels[_model].w;
            double full = (double)portraitH(_model, baseW(_model, YES)) / baseW(_model, YES);
            if (fabs(r - half) < fabs(r - full)) {
                _w = (int)lround(_w * (double)baseW(_model, YES) / kModels[_model].w / STEP) * STEP;
                _h = [self defaultH:_model w:_w];
            }
        }
    }
    SizeRange r = sizeRange(_model);
    _w = MAX(r.wmin, MIN(r.wmax, _w));
    _h = MAX(r.hmin, MIN(r.hmax, _h));
    _ratio = (double)_h / _w;
}

// 设备宽度为 w 时的推荐高度：手机全屏时铺满整块屏，否则按设备推荐尺寸等比
- (int)defaultH:(int)m w:(int)w {
    if (_full && !modelIsDesktop(m)) {
        return portraitH(m, w);
    }
    return (int)lround((double)w * kModels[m].h / kModels[m].w / STEP) * STEP;
}

- (void)save {
    [self.ud setObject:@(kModels[_model].name) forKey:@"model"];
    [self.ud setInteger:_w forKey:@"w"];
    [self.ud setInteger:_h forKey:@"h"];
}

// 当前尺寸和哪个预设完全一样，没有返回 -1
- (NSInteger)matchingPreset {
    NSArray *ps = self.presets;
    for (NSInteger i = 0; i < (NSInteger)ps.count; i++) {
        NSDictionary *d = ps[i];
        if (modelIndexByName(d[@"model"]) == _model && [d[@"w"] intValue] == _w && [d[@"h"] intValue] == _h) {
            return i;
        }
    }
    return -1;
}

#pragma mark 界面

static NSTextField *label(NSString *s, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSTextField *t = [NSTextField labelWithString:s];
    t.font = [NSFont systemFontOfSize:size weight:weight];
    t.textColor = color;
    [t sizeToFit];
    return t;
}

static NSTextField *numLabel(CGFloat width) {
    NSTextField *t = label(@"", 13, NSFontWeightRegular, NSColor.secondaryLabelColor);
    t.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular];
    t.alignment = NSTextAlignmentRight;
    t.frame = NSMakeRect(0, 0, width, 17);
    return t;
}

static void separator(NSView *v, CGFloat y) {
    NSBox *s = [[NSBox alloc] initWithFrame:NSMakeRect(PAD, y, PANEL_W - PAD * 2, 1)];
    s.boxType = NSBoxSeparator;
    [v addSubview:s];
}

// 圆形底上一枚图标，行顶在 y。filled：强调色实心底白图标；否则灰底、和文字同色的图标
static void chip(NSView *v, CGFloat y, NSString *sym, BOOL filled) {
    NSBox *b = [[NSBox alloc] initWithFrame:NSMakeRect(PAD, y + 8, 28, 28)];
    b.boxType = NSBoxCustom;
    b.titlePosition = NSNoTitle;
    b.borderWidth = 0;
    b.cornerRadius = 14;
    b.fillColor = filled ? NSColor.controlAccentColor : ChipFill();
    [v addSubview:b];
    NSImageView *iv = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:sym
                                                                accessibilityDescription:nil]];
    iv.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightMedium];
    iv.contentTintColor = filled ? NSColor.whiteColor : NSColor.labelColor;
    iv.frame = NSMakeRect(PAD + 3, y + 11, 22, 22);
    [v addSubview:iv];
}

// 一行（行顶在 y、高 ROW_H）的左半边：圆形图标加标题
static NSTextField *rowTitle(NSView *v, CGFloat y, NSString *sym, BOOL filled, NSString *title) {
    chip(v, y, sym, filled);
    NSTextField *t = label(title, 13, NSFontWeightRegular, NSColor.labelColor);
    [t setFrameOrigin:NSMakePoint(TITLE_X, y + floor((ROW_H - t.frame.size.height) / 2))];
    [v addSubview:t];
    return t;
}

// 把控件放到行顶为 y 的那一行右侧，右边留 right 的空
static void placeRight(NSView *v, CGFloat y, NSView *c, CGFloat right) {
    NSSize s = c.frame.size;
    c.frame = NSMakeRect(PANEL_W - PAD - right - s.width, y + floor((ROW_H - s.height) / 2), s.width, s.height);
    [v addSubview:c];
}

- (void)buildPanel {
    FlipView *r = [[FlipView alloc] initWithFrame:NSMakeRect(0, 0, PANEL_W, 100)];
    self.root = r;

    // 标题、状态和总开关
    NSTextField *t = label(L(@"远程模式"), 15, NSFontWeightSemibold, NSColor.labelColor);
    [t setFrameOrigin:NSMakePoint(PAD, 14)];
    [r addSubview:t];
    self.stateLabel = label(@"", 12, NSFontWeightRegular, NSColor.secondaryLabelColor);
    self.stateLabel.frame = NSMakeRect(PAD, 36, 220, 16);
    [r addSubview:self.stateLabel];
    self.power = [NSSwitch new];
    [self.power sizeToFit];
    [self.power setFrameOrigin:NSMakePoint(PANEL_W - PAD - self.power.frame.size.width,
                                           floor((66 - self.power.frame.size.height) / 2))];
    self.power.target = self;
    self.power.action = @selector(powerClicked:);
    [r addSubview:self.power];
    separator(r, 66);

    // 跟随 UU 远程：UU 连上自动开，断开自动关
    CGFloat y = 72;
    rowTitle(r, y, @"antenna.radiowaves.left.and.right", NO, L(@"跟随 UU 远程"));
    self.followUU = [NSSwitch new];
    self.followUU.controlSize = NSControlSizeSmall;
    [self.followUU sizeToFit];
    self.followUU.state = [self.ud objectForKey:@"followUU"] && ![self.ud boolForKey:@"followUU"] ? NSControlStateValueOff
                                                                                                   : NSControlStateValueOn;
    self.followUU.target = self;
    self.followUU.action = @selector(followClicked:);
    self.followUU.toolTip = L(@"网易 UU 远程连上时自动开启远程画面，断开时自动关闭");
    placeRight(r, y, self.followUU, 0);

    // 设备：手机按品牌、系列分层，电脑排在后面
    y += ROW_H;
    rowTitle(r, y, @"laptopcomputer.and.iphone", NO, L(@"设备"));
    self.modelBtn = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 180, 24) pullsDown:YES];
    self.modelBtn.bordered = NO;
    self.modelBtn.alignment = NSTextAlignmentRight;
    self.modelBtn.menu.delegate = self;
    placeRight(r, y, self.modelBtn, -4);

    // 手机画面：全屏铺满，或半屏留出输入法
    // 这一行和下面的内容各放一个容器：选电脑时藏起这一行，下面整体上移
    y += ROW_H;
    self.phoneRow = [[FlipView alloc] initWithFrame:NSMakeRect(0, y, PANEL_W, ROW_H)];
    [r addSubview:self.phoneRow];
    rowTitle(self.phoneRow, 0, @"rectangle.portrait", NO, L(@"手机画面"));
    self.fullSeg = [NSSegmentedControl segmentedControlWithLabels:@[ L(@"全屏"), L(@"半屏") ]
                                                     trackingMode:NSSegmentSwitchTrackingSelectOne
                                                           target:self
                                                           action:@selector(fullClicked:)];
    self.fullSeg.controlSize = NSControlSizeSmall;
    [self.fullSeg sizeToFit];
    self.fullSeg.toolTip = L(@"全屏：画面铺满手机屏幕。半屏：下面留出输入法的位置");
    placeRight(self.phoneRow, 0, self.fullSeg, 0);
    self.lowerBox = [[FlipView alloc] initWithFrame:NSMakeRect(0, y + ROW_H, PANEL_W, 10)];
    [r addSubview:self.lowerBox];
    FlipView *v = self.lowerBox;

    // 显示大小：标题行右侧是分辨率和相对机型推荐宽度的比例，下面一整条滑块，两端写方向
    y = 0;
    rowTitle(v, y, @"textformat.size", NO, L(@"显示大小"));
    self.sizeLabel = numLabel(150);
    placeRight(v, y, self.sizeLabel, 0);
    self.slider = [NSSlider sliderWithValue:WMIN minValue:WMIN maxValue:WMAX target:self action:@selector(slid:)];
    self.slider.frame = NSMakeRect(PAD - 2, y + 40, PANEL_W - PAD * 2 + 4, 24);
    self.slider.numberOfTickMarks = 7;
    [v addSubview:self.slider];
    NSTextField *l = label(L(@"更大文本"), 11, NSFontWeightRegular, NSColor.secondaryLabelColor);
    [l setFrameOrigin:NSMakePoint(PAD, y + 66)];
    [v addSubview:l];
    NSTextField *m = label(L(@"更多空间"), 11, NSFontWeightRegular, NSColor.secondaryLabelColor);
    [m setFrameOrigin:NSMakePoint(PANEL_W - PAD - m.frame.size.width, y + 66)];
    [v addSubview:m];

    // 画面高度：数字加「− | +」，每点一下 ±10
    y += SIZE_H;
    rowTitle(v, y, @"arrow.up.and.down", NO, L(@"画面高度"));
    self.heightSeg = [NSSegmentedControl
        segmentedControlWithImages:@[
            [NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:L(@"调矮")],
            [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:L(@"调高")]
        ]
                      trackingMode:NSSegmentSwitchTrackingMomentary
                            target:self
                            action:@selector(stepped:)];
    [self.heightSeg setWidth:30 forSegment:0];
    [self.heightSeg setWidth:30 forSegment:1];
    [self.heightSeg sizeToFit];
    self.heightSeg.toolTip = L(@"只改高度。手机上画面底部被输入法挡住、电脑上远程窗口没全屏时调矮");
    placeRight(v, y, self.heightSeg, -2);
    self.heightLabel = numLabel(60);
    placeRight(v, y, self.heightLabel, self.heightSeg.frame.size.width + 6);

    // 滚动速度：只调 UU 远程发来的滚动，100% 是原速。装了 Mos 这类平滑滚动工具的会被放大，要往低调；没装的嫌慢可以调快
    y += ROW_H;
    rowTitle(v, y, @"scroll", NO, L(@"滚动速度"));
    self.scrollBtn = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 90, 24) pullsDown:NO];
    self.scrollBtn.bordered = NO;
    for (NSNumber *pct in @[ @200, @150, @100, @70, @50, @35, @25, @18, @12 ]) {
        NSString *t = [NSString stringWithFormat:@"%@%%", pct];
        [self.scrollBtn addItemWithTitle:pct.integerValue == 100 ? [NSString stringWithFormat:@"%@ %@", t, L(@"原速")] : t];
        self.scrollBtn.lastItem.tag = pct.integerValue;
    }
    [self.scrollBtn sizeToFit];
    self.scrollBtn.target = self;
    self.scrollBtn.action = @selector(scrollPicked:);
    self.scrollBtn.toolTip = L(@"调整手机上滑动的滚动速度，只影响 UU 远程，不影响本机鼠标和触控板。第一次调整要在系统设置里允许辅助功能");
    placeRight(v, y, self.scrollBtn, -4);
    if (![self.scrollBtn selectItemWithTag:[self scrollPct]]) {
        [self.scrollBtn selectItemWithTag:100];
    }

    y += ROW_H + 6;
    separator(v, y);

    // 预设区：标题、各条预设、新建预设、退出。条数会变，放进单独的容器里重排
    self.presetBox = [[FlipView alloc] initWithFrame:NSMakeRect(0, y + 1, PANEL_W, 10)];
    [v addSubview:self.presetBox];

    NSViewController *vc = [NSViewController new];
    vc.view = r;
    self.popover = [NSPopover new];
    self.popover.contentViewController = vc;
    self.popover.behavior = NSPopoverBehaviorTransient;
    self.popover.delegate = self;
    [self buildPresets];
}

// 重排预设区，面板高度跟着变。预设增删、覆盖时调；改名只改那一行，不重排
- (void)buildPresets {
    FlipView *b = self.presetBox;
    for (NSView *v in [b.subviews copy]) {
        [v removeFromSuperview];
    }
    NSTextField *h = label(L(@"预设"), 12, NSFontWeightMedium, NSColor.secondaryLabelColor);
    [h setFrameOrigin:NSMakePoint(PAD, 10)];
    [b addSubview:h];
    CGFloat y = 30;
    NSArray *ps = self.presets;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)ps.count; i++) {
        PresetRow *r = [[PresetRow alloc] initWithFrame:NSMakeRect(0, y, PANEL_W, PRESET_H)
                                                   name:ps[i][@"name"]
                                                 detail:[NSString stringWithFormat:@"%@ × %@", ps[i][@"w"], ps[i][@"h"]]];
        __weak AppDelegate *me = self;
        r.onPick = ^{
            [me applyPreset:i];
        };
        r.onRename = ^(NSString *name) {
            [me savePreset:i name:name];
        };
        NSMenu *m = [NSMenu new];
        for (NSArray *it in @[ @[ L(@"重命名"), @"renamePreset:" ], @[ L(@"用当前尺寸覆盖"), @"overwritePreset:" ],
                               @[ L(@"删除"), @"deletePreset:" ] ]) {
            NSMenuItem *mi = [m addItemWithTitle:it[0] action:NSSelectorFromString(it[1]) keyEquivalent:@""];
            mi.target = self;
            mi.tag = i;
        }
        r.menu = m;
        r.toolTip = L(@"点一下切换，双击改名，右键可覆盖或删除");
        [b addSubview:r];
        [rows addObject:r];
        y += PRESET_H;
    }
    self.presetRows = rows;

    // 新建预设：当前尺寸已经存过时变淡、点不了
    y -= 4;
    self.addRow = [[ClickRow alloc] initWithFrame:NSMakeRect(0, y, PANEL_W, ROW_H)];
    rowTitle(self.addRow, 0, @"plus", YES, L(@"新建预设"));
    __weak AppDelegate *me = self;
    self.addRow.onClick = ^{
        [me addPreset];
    };
    [b addSubview:self.addRow];
    y += ROW_H + 2;
    separator(b, y);
    // 检查更新：右边写当前版本
    ClickRow *upd = [[ClickRow alloc] initWithFrame:NSMakeRect(0, y + 2, PANEL_W, 36)];
    NSImageView *ui = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"arrow.triangle.2.circlepath"
                                                                accessibilityDescription:nil]];
    ui.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightRegular];
    ui.contentTintColor = NSColor.labelColor;
    ui.frame = NSMakeRect(PAD, floor((36 - 18) / 2), 18, 18);
    [upd addSubview:ui];
    NSTextField *ul = label(L(@"检查更新"), 13, NSFontWeightRegular, NSColor.labelColor);
    [ul setFrameOrigin:NSMakePoint(PAD + 26, floor((36 - ul.frame.size.height) / 2))];
    [upd addSubview:ul];
    NSString *ver = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSTextField *uv = label([@"v" stringByAppendingString:ver], 13, NSFontWeightRegular, NSColor.secondaryLabelColor);
    [uv setFrameOrigin:NSMakePoint(PANEL_W - PAD - uv.frame.size.width, floor((36 - uv.frame.size.height) / 2))];
    [upd addSubview:uv];
    upd.onClick = ^{
        [me.popover performClose:nil];
        [[Updater shared] checkNow];
    };
    [b addSubview:upd];
    self.updateRow = upd;
    y += 36;

    // 退出：和菜单里的退出一样，左边方框叉图标，右边写快捷键 ⌘Q
    ClickRow *quit = [[ClickRow alloc] initWithFrame:NSMakeRect(0, y + 2, PANEL_W, 36)];
    NSImageView *qi = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"xmark.square"
                                                                accessibilityDescription:nil]];
    qi.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightRegular];
    qi.contentTintColor = NSColor.labelColor;
    qi.frame = NSMakeRect(PAD, floor((36 - 18) / 2), 18, 18);
    [quit addSubview:qi];
    NSTextField *q = label(L(@"退出"), 13, NSFontWeightRegular, NSColor.labelColor);
    [q setFrameOrigin:NSMakePoint(PAD + 26, floor((36 - q.frame.size.height) / 2))];
    [quit addSubview:q];
    NSTextField *k = label(@"⌘Q", 13, NSFontWeightRegular, NSColor.secondaryLabelColor);
    [k setFrameOrigin:NSMakePoint(PANEL_W - PAD - k.frame.size.width, floor((36 - k.frame.size.height) / 2))];
    [quit addSubview:k];
    quit.onClick = ^{
        [NSApp terminate:nil];
    };
    [b addSubview:quit];
    self.quitRow = quit;
    y += 42;

    b.frame = NSMakeRect(0, b.frame.origin.y, PANEL_W, y);
    self.lowerBox.frame = NSMakeRect(0, self.lowerBox.frame.origin.y, PANEL_W, NSMaxY(b.frame));
    [self refresh];
}

// 显示大小能拖到的宽度：比例不变时高度也要在允许范围内
- (void)sliderRange:(double *)lo hi:(double *)hi {
    SizeRange r = sizeRange(_model);
    *lo = MAX(r.wmin, ceil(r.hmin / _ratio));
    *hi = MIN(r.wmax, floor(r.hmax / _ratio));
}

- (void)refresh {
    // 等 Crisp 这类工具退出的那几秒也算「正在开启」
    BOOL waiting = otherAppsQuitting();
    BOOL on = displayIsOn() || waiting, closing = displayIsClosing(), mirrored = displayIsMirrored();
    BOOL ready = on && mirrored && !closing;
    self.power.state = on && !closing ? NSControlStateValueOn : NSControlStateValueOff;
    self.power.enabled = !closing && !waiting && !_terminating;
    NSString *st = closing ? L(@"正在关闭") : !on ? L(@"已关闭") : ready ? L(@"已开启") : L(@"正在开启");
    self.stateLabel.stringValue = ready ? [NSString stringWithFormat:@"%@ · %d × %d", st, _w, _h] : st;
    self.stateLabel.textColor = ready ? NSColor.controlAccentColor : NSColor.secondaryLabelColor;
    self.statusItem.button.image = statusImage(on);

    [self.modelBtn.menu removeAllItems];
    [self.modelBtn addItemWithTitle:shownText(kModels[_model].name)];
    [self.modelBtn sizeToFit];
    NSRect f = self.modelBtn.frame;
    CGFloat w = MIN(f.size.width, PANEL_W - TITLE_X - 70);
    self.modelBtn.frame = NSMakeRect(PANEL_W - PAD + 4 - w, f.origin.y, w, f.size.height);

    // 比例：相对机型推荐宽度，越大一屏放的内容越多
    self.sizeLabel.stringValue =
        [NSString stringWithFormat:@"%d × %d · %ld%%", _w, _h, lround(_w * 100.0 / baseW(_model, _full))];
    double lo, hi;
    [self sliderRange:&lo hi:&hi];
    self.slider.minValue = lo;
    self.slider.maxValue = hi;
    self.slider.doubleValue = _w;
    self.heightLabel.stringValue = [NSString stringWithFormat:@"%d", _h];
    self.fullSeg.selectedSegment = _full ? 0 : 1;
    [self layoutPanel];

    NSInteger match = [self matchingPreset];
    for (NSUInteger i = 0; i < self.presetRows.count; i++) {
        self.presetRows[i].checked = (NSInteger)i == match;
    }
    self.addRow.enabled = match < 0;
}

// 电脑不分全屏半屏：藏起「手机画面」这一行，下面整体上移，面板高度跟着变
- (void)layoutPanel {
    BOOL desk = modelIsDesktop(_model);
    self.phoneRow.hidden = desk;
    NSRect lf = self.lowerBox.frame;
    lf.origin.y = desk ? NSMinY(self.phoneRow.frame) : NSMaxY(self.phoneRow.frame);
    self.lowerBox.frame = lf;
    NSRect f = self.root.frame;
    f.size.height = NSMaxY(lf);
    if (f.size.height != self.root.frame.size.height) {
        self.root.frame = f;
        self.popover.contentSize = f.size;
    }
}

// 滚动速度百分比，没设过是 100
- (NSInteger)scrollPct {
    NSInteger p = [self.ud integerForKey:@"scrollPct"];
    return p > 0 && p <= 200 ? p : 100;
}

- (void)scrollPicked:(NSPopUpButton *)b {
    [self.ud setInteger:b.selectedTag forKey:@"scrollPct"];
    if (!scrollSpeedSet(b.selectedTag / 100.0)) {
        // 还没授权：收起面板，让系统的授权提示露出来。授权后自动生效
        [self.popover performClose:nil];
    }
}

#pragma mark 机型菜单

// 机型项右侧带推荐尺寸
- (void)addModel:(int)i to:(NSMenu *)m {
    NSMenuItem *it = [m addItemWithTitle:shownText(kModels[i].name) action:@selector(pickModel:) keyEquivalent:@""];
    it.target = self;
    it.tag = i;
    it.state = i == _model ? NSControlStateValueOn : NSControlStateValueOff;
    NSFont *f = [NSFont menuFontOfSize:0];
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.tabStops = @[ [[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentRight location:220 options:@{}] ];
    NSMutableAttributedString *as =
        [[NSMutableAttributedString alloc] initWithString:it.title
                                               attributes:@{NSFontAttributeName : f, NSParagraphStyleAttributeName : ps}];
    [as appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:[NSString stringWithFormat:@"\t%d × %d", baseW(i, _full),
                                                                             [self defaultH:i w:baseW(i, _full)]]
                                       attributes:@{
                                           NSFontAttributeName : [NSFont monospacedDigitSystemFontOfSize:f.pointSize - 1
                                                                                                 weight:NSFontWeightRegular],
                                           NSForegroundColorAttributeName : NSColor.secondaryLabelColor,
                                           NSParagraphStyleAttributeName : ps
                                       }]];
    it.attributedTitle = as;
}

// 点开设备菜单时现搭：第一项是按钮标题，然后每个品牌一个子菜单，有系列的（iPhone 按代）再分一层。手机和电脑之间加分隔线
- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    [menu addItemWithTitle:shownText(kModels[_model].name) action:nil keyEquivalent:@""];
    BOOL sawDesktop = NO;
    for (NSString *g in groupNames()) {
        int first = firstModelOfGroup((int)[groupNames() indexOfObject:g]);
        if (modelIsDesktop(first) && !sawDesktop) {
            sawDesktop = YES;
            [menu addItem:[NSMenuItem separatorItem]];
        }
        NSMenu *gm = [NSMenu new];
        NSMenu *sub = nil;
        for (int i = 0; i < NMODEL; i++) {
            if (![g isEqualToString:@(kModels[i].group)]) {
                continue;
            }
            if (!kModels[i].series) {
                [self addModel:i to:gm];
                continue;
            }
            if (i == 0 || !kModels[i - 1].series || strcmp(kModels[i - 1].series, kModels[i].series) != 0) {
                sub = [NSMenu new];
                NSMenuItem *si = [gm addItemWithTitle:shownText(kModels[i].series) action:nil keyEquivalent:@""];
                si.submenu = sub;
                BOOL cur = kModels[_model].series && strcmp(kModels[_model].series, kModels[i].series) == 0;
                si.state = cur ? NSControlStateValueOn : NSControlStateValueOff;
            }
            [self addModel:i to:sub];
        }
        NSMenuItem *gi = [menu addItemWithTitle:NSLocalizedString(g, nil) action:nil keyEquivalent:@""];
        gi.submenu = gm;
        gi.state = [g isEqualToString:@(kModels[_model].group)] ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)menuDidClose:(NSMenu *)menu {
    [self refresh];
}

#pragma mark 操作

- (void)setW:(int)w h:(int)h {
    [self showW:w h:h];
    [self scheduleApply:0.25];
}

// 只改数值和界面，不碰虚拟屏（拖滑块的过程中用）
- (void)showW:(int)w h:(int)h {
    SizeRange r = sizeRange(_model);
    _w = MAX(r.wmin, MIN(r.wmax, w));
    _h = MAX(r.hmin, MIN(r.hmax, h));
    [self refresh];
}

// 每换一次分辨率，系统要重新配置虚拟屏和镜像它的物理屏，连着换会排队，
// 所以两次之间至少隔 APPLY_GAP 秒；期间再有改动只记最后一次
#define APPLY_GAP 1.5
static CFAbsoluteTime lastApply;

- (void)scheduleApply:(double)delay {
    double wait = MAX(delay, lastApply + APPLY_GAP - CFAbsoluteTimeGetCurrent());
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyNow) object:nil];
    [self performSelector:@selector(applyNow) withObject:nil afterDelay:wait];
}

- (void)applyNow {
    if (displayIsOn() && !displayIsClosing()) {
        lastApply = CFAbsoluteTimeGetCurrent();
    }
    displayResize(_w, _h, sizeRange(_model));
    [self save];
}

// 换一整套尺寸（设备、预设）：比例跟着换。手机和电脑之间切换也只是换档位，虚拟屏不重建
- (void)useModel:(int)m w:(int)w h:(int)h {
    _model = m;
    SizeRange r = sizeRange(m);
    _ratio = (double)MAX(r.hmin, MIN(r.hmax, h)) / MAX(r.wmin, MIN(r.wmax, w));
    [self setW:w h:h];
}

// 显示大小：宽度按 10 取整，高度按比例算。拖动中只更新数字，松手才应用
- (void)slid:(NSSlider *)s {
    int w = (int)lround(s.doubleValue / STEP) * STEP;
    double lo, hi;
    [self sliderRange:&lo hi:&hi];
    w = (int)MAX(lo, MIN(hi, w));
    // 鼠标键还按着就是在拖。不看事件类型：新系统的滑块拖动时事件类型不一定是拖动
    BOOL dragging = (NSEvent.pressedMouseButtons & 1) != 0;
    if (w != _w) {
        [self showW:w h:(int)lround(w * _ratio)];
    }
    if (!dragging) {
        [self scheduleApply:0];
    }
}

// 画面高度：点 − 或 + 每次 ±10，宽度不动
- (void)stepped:(NSSegmentedControl *)s {
    int d = s.selectedSegment == 0 ? -1 : 1;
    SizeRange r = sizeRange(_model);
    int h = MAX(r.hmin, MIN(r.hmax, _h + d * STEP));
    _ratio = (double)h / _w;
    [self setW:_w h:h];
}

- (void)pickModel:(NSMenuItem *)it {
    if (it.tag < 0 || it.tag >= NMODEL) {
        return;
    }
    int m = (int)it.tag;
    [self useModel:m w:baseW(m, _full) h:[self defaultH:m w:baseW(m, _full)]];
}

// 全屏、半屏：显示大小的百分比不变，宽高换成对应的推荐尺寸。只在选了手机时显示
- (void)fullClicked:(NSSegmentedControl *)s {
    double pct = (double)_w / baseW(_model, _full);
    _full = s.selectedSegment == 0;
    [self.ud setBool:_full forKey:@"full"];
    int w = (int)lround(baseW(_model, _full) * pct / STEP) * STEP;
    [self useModel:_model w:w h:[self defaultH:_model w:w]];
}

- (void)applyPreset:(NSInteger)i {
    NSArray *ps = self.presets;
    if (i >= (NSInteger)ps.count) {
        return;
    }
    NSDictionary *d = ps[i];
    int mi = modelIndexByName(d[@"model"]);
    [self useModel:mi >= 0 ? mi : _model w:[d[@"w"] intValue] h:[d[@"h"] intValue]];
}

// 新建预设：名字先填机型加尺寸，随即进入改名，直接打字替换，回车确认
- (void)addPreset {
    if ([self matchingPreset] >= 0) {
        return;
    }
    NSMutableArray *ps = [self.presets mutableCopy];
    [ps addObject:@{
        @"name" : [NSString stringWithFormat:@"%@ %d×%d", shownText(kModels[_model].name), _w, _h],
        @"model" : @(kModels[_model].name),
        @"w" : @(_w),
        @"h" : @(_h)
    }];
    [self setPresets:ps];
    [self.presetRows.lastObject beginRename];
}

// 改名：只存设置，那一行已经自己显示新名字
- (void)savePreset:(NSInteger)i name:(NSString *)name {
    NSMutableArray *ps = [self.presets mutableCopy];
    if (i >= (NSInteger)ps.count) {
        return;
    }
    NSMutableDictionary *d = [ps[i] mutableCopy];
    d[@"name"] = name;
    ps[i] = d;
    [self.ud setObject:ps forKey:@"presets"];
}

- (void)renamePreset:(NSMenuItem *)it {
    if (it.tag < (NSInteger)self.presetRows.count) {
        [self.presetRows[it.tag] beginRename];
    }
}

// 面板收起前结束正在进行的改名，名字才存得下来
- (void)popoverWillClose:(NSNotification *)n {
    // 鼠标停在某一行上就收起面板时，系统不会再发移出事件，下次打开还是高亮的：这里统一清掉
    for (PresetRow *r in self.presetRows) {
        [r clearHover];
    }
    [self.addRow clearHover];
    [self.updateRow clearHover];
    [self.quitRow clearHover];
    [self.root.window makeFirstResponder:nil];
}

- (void)overwritePreset:(NSMenuItem *)it {
    NSMutableArray *ps = [self.presets mutableCopy];
    if (it.tag >= (NSInteger)ps.count) {
        return;
    }
    NSMutableDictionary *d = [ps[it.tag] mutableCopy];
    d[@"model"] = @(kModels[_model].name);
    d[@"w"] = @(_w);
    d[@"h"] = @(_h);
    ps[it.tag] = d;
    [self setPresets:ps];
}

- (void)deletePreset:(NSMenuItem *)it {
    NSMutableArray *ps = [self.presets mutableCopy];
    if (it.tag >= (NSInteger)ps.count) {
        return;
    }
    [ps removeObjectAtIndex:it.tag];
    [self setPresets:ps];
}

#pragma mark 开关

// 开或关远程画面。关闭是异步的，期间开关不可用
- (void)setRemoteOn:(BOOL)on {
    if (displayIsClosing() || otherAppsQuitting() || _terminating) {
        return;
    }
    if (on) {
        otherAppsQuitThen(^{
            [self turnOn];
        });
    } else {
        displayOff(^{
            otherAppsRelaunch();
            [self refresh];
            [[Updater shared] installPendingIfReady]; // 远程画面开着时下好的更新，关掉后装
        });
    }
    [self refresh];
}

// 其他虚拟屏工具让开之后才建虚拟屏。等的期间用户要退出程序，就不建了，把它们打开后放行退出
- (void)turnOn {
    if (_terminating) {
        otherAppsRelaunch();
        [NSApp replyToApplicationShouldTerminate:YES];
        return;
    }
    if (!displayOn(_w, _h, sizeRange(_model))) {
        otherAppsRelaunch();
        NSAlert *a = [NSAlert new];
        a.messageText = L(@"虚拟屏创建失败");
        a.informativeText = L(@"需要 macOS 12 或更新的版本。");
        [a runModal];
    }
    [self refresh];
}

- (void)powerClicked:(NSSwitch *)s {
    [self setRemoteOn:s.state == NSControlStateValueOn];
}

- (void)followClicked:(NSSwitch *)s {
    [self.ud setBool:s.state == NSControlStateValueOn forKey:@"followUU"];
}

// UU 连上、断开的那一刻才动作：连着时手动关掉远程画面，不会被打开回来
- (void)uuChanged:(BOOL)connected {
    if (self.followUU.state != NSControlStateValueOn || displayIsPreview()) {
        return;
    }
    BOOL on = displayIsOn() || otherAppsQuitting();
    if (connected != on) {
        [self setRemoteOn:connected];
    }
}

// 显示器那边有变化：镜像设好了，或者虚拟屏被系统回收了。回收后按当前尺寸自动重建，一分钟内最多三次，免得反复失败时闪个不停
- (void)displayEvent:(BOOL)lost {
    if (lost && !_terminating) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - _rebuildT0 > 60) {
            _rebuildT0 = now;
            _rebuilds = 0;
        }
        if (++_rebuilds > 3 || !displayOn(_w, _h, sizeRange(_model))) {
            displayAbandon();
        }
    }
    // 虚拟屏放弃重建，或者排列一直被改掉而自动关闭了：远程画面已经关掉，把让出来的工具打开
    if (!displayIsOn() && !displayIsClosing() && !otherAppsQuitting() && !_terminating) {
        otherAppsRelaunch();
        [[Updater shared] installPendingIfReady];
    }
    [self refresh];
}

- (void)didWake:(NSNotification *)n {
    displayScheduleVerify();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        displayScheduleVerify();
    });
}

#pragma mark 应用生命周期

// 菜单栏图标：圆角方块里一道折线，模板图跟随菜单栏深浅色。关闭时方块是空心的，开启时是实心的、折线镂空
static NSImage *statusImage(BOOL on) {
    NSImage *im = [NSImage imageWithSize:NSMakeSize(18, 18)
                                 flipped:NO
                          drawingHandler:^BOOL(NSRect r) {
                              NSBezierPath *p = [NSBezierPath bezierPath];
                              // 整体比画布中线低 0.75：和 PicBox 菜单栏图标的视觉重心对齐
                              [p moveToPoint:NSMakePoint(4.5, 7)];
                              [p lineToPoint:NSMakePoint(8, 10.5)];
                              [p lineToPoint:NSMakePoint(10, 6.5)];
                              [p lineToPoint:NSMakePoint(13.5, 10)];
                              p.lineWidth = 1.8;
                              p.lineCapStyle = NSLineCapStyleRound;
                              p.lineJoinStyle = NSLineJoinStyleRound;
                              [NSColor.blackColor set];
                              if (on) {
                                  [RR(NSMakeRect(1, 1.25, 16, 14), 4) fill];
                                  [NSGraphicsContext.currentContext setCompositingOperation:NSCompositingOperationClear];
                              } else {
                                  // 方框线宽 1.5，和 PicBox 菜单栏图标的线条轻重对齐
                                  NSBezierPath *box = RR(NSMakeRect(1.5, 1.75, 15, 13), 3.5);
                                  box.lineWidth = 1.5;
                                  [box stroke];
                              }
                              [p stroke];
                              return YES;
                          }];
    im.template = YES;
    return im;
}

- (void)togglePanel:(id)sender {
    if (self.popover.shown) {
        [self.popover performClose:nil];
        return;
    }
    [self refresh];
    [NSApp activateIgnoringOtherApps:YES];
    [self.popover showRelativeToRect:self.statusItem.button.bounds
                              ofView:self.statusItem.button
                       preferredEdge:NSRectEdgeMinY];
    // 面板设的是点外面自动收起，但系统只在本程序处于激活状态时才管；新版 macOS 不一定让菜单栏程序激活，
    // 点桌面、别的窗口、别的菜单栏图标时面板就不收。自己监听：别的程序里一有鼠标按下就收起
    if (!self.outsideClick) {
        __weak AppDelegate *me = self;
        self.outsideClick = [NSEvent
            addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown
                                          handler:^(NSEvent *e) {
                                              [me.popover performClose:nil];
                                          }];
    }
}

- (void)savePanelShot:(NSString *)path {
    [self refresh];
    NSView *v = self.popover.contentViewController.view;
    // 不在屏幕上的视图要放进一个窗口里才按外观画背景和控件
    NSWindow *w = [[NSWindow alloc] initWithContentRect:v.bounds styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    w.appearance = NSApp.appearance;
    w.backgroundColor = NSColor.windowBackgroundColor;
    w.contentView = v;
    [v layoutSubtreeIfNeeded];
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [w.contentView cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

- (void)popoverDidClose:(NSNotification *)n {
    if (self.outsideClick) {
        [NSEvent removeMonitor:self.outsideClick];
        self.outsideClick = nil;
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    // 隐藏的主菜单，只放一个退出：面板打开时按 ⌘Q 能退出（面板上的退出行写着 ⌘Q）
    NSMenu *mainMenu = [NSMenu new];
    NSMenu *appMenu = [NSMenu new];
    [appMenu addItemWithTitle:L(@"退出") action:@selector(terminate:) keyEquivalent:@"q"];
    [mainMenu addItemWithTitle:@"" action:nil keyEquivalent:@""].submenu = appMenu;
    NSApp.mainMenu = mainMenu;
    [self load];
    scrollSpeedSet([self scrollPct] / 100.0);
    // 菜单栏图标默认放在控制中心左边紧挨着：远程画面窄，排在后面的图标会被挤掉看不见。
    // 数值是离屏幕右边的距离，越小越靠右；用户按住 ⌘ 拖过之后系统会改写它，这里只在没有时写
    NSString *pos = @"NSStatusItem Preferred Position Item-0";
    if (![self.ud objectForKey:pos]) {
        [self.ud setDouble:200 forKey:pos];
    }
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.toolTip = L(@"远程模式");
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(togglePanel:);
    [self buildPanel];
    // 不让系统对本程序做 App Nap：被降频的话定时器会晚很多，关闭时等虚拟屏下线靠定时器
    self.activity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiatedAllowingIdleSystemSleep
                                                                   reason:@"控制虚拟显示器"];
    __weak AppDelegate *me = self;
    displaySetEventHandler(^(BOOL lost) {
        [me displayEvent:lost];
    });
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(didWake:)
                                                               name:NSWorkspaceDidWakeNotification
                                                             object:nil];
    // 检查更新：远程画面开着、正在关闭、等别的工具退出时都先不装
    [Updater shared].canInstallNow = ^BOOL {
        return !displayIsOn() && !displayIsClosing() && !otherAppsQuitting() && !displayIsPreview();
    };
    if (!displayIsPreview()) {
        [[Updater shared] startWithRepo:@"cyanext/PhoneMode"];
    }
    // 打开时不自动开远程画面。上次被强杀或崩溃时物理屏没恢复、让出来的工具也没打开：这里补上
    displayRecoverFromCrash();
    otherAppsRelaunch();
    endEditingOnOutsideClick();
    uuWatchStart(^(BOOL connected) {
        [me uuChanged:connected];
    });
    [self refresh];
    // 打开时弹出面板，让人知道它在菜单栏
    dispatch_async(dispatch_get_main_queue(), ^{
        [self togglePanel:nil];
    });
}

// 退出前先把显示器恢复好：恢复是异步的，这里先答复「稍后」，恢复完成再放行
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)s {
    [self save];
    if (_terminating) {
        return NSTerminateLater;
    }
    // 正在等其他工具退出：等它们退完，由 turnOn 把它们打开后放行
    if (otherAppsQuitting()) {
        _terminating = YES;
        [self refresh];
        return NSTerminateLater;
    }
    if (!displayIsOn() && !displayIsClosing()) {
        otherAppsRelaunch();
        return NSTerminateNow;
    }
    _terminating = YES;
    displayOff(^{
        otherAppsRelaunch();
        [NSApp replyToApplicationShouldTerminate:YES];
    });
    [self refresh];
    return NSTerminateLater;
}

// 已经在运行时再次打开（比如在访达里双击）：弹出面板
- (BOOL)applicationShouldHandleReopen:(NSApplication *)s hasVisibleWindows:(BOOL)f {
    if (!self.popover.shown) {
        [self togglePanel:nil];
    }
    return NO;
}

- (void)applicationWillTerminate:(NSNotification *)n {
    [self save];
    displayOffSync();
    otherAppsRelaunch();
}

@end
