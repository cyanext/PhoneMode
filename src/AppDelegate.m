#import "AppDelegate.h"
#import "DisplayControl.h"
#import "OtherApps.h"
#import "PhoneModels.h"
#import "Theme.h"
#import "UUWatch.h"

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
@property(strong) FlipView *root, *presetBox;
@property(strong) NSSwitch *power, *followUU;
@property(strong) NSTextField *stateLabel, *sizeLabel, *heightLabel;
@property(strong) NSPopUpButton *modelBtn;
@property(strong) NSSlider *slider;
@property(strong) NSSegmentedControl *heightSeg;
@property(strong) id<NSObject> activity;
@end

@implementation AppDelegate {
    int _model, _w, _h, _rebuilds;
    // 宽高比（高 ÷ 宽）。拖显示大小时保持不变；选机型、选预设、调画面高度时重算
    double _ratio;
    BOOL _terminating;
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
        [out addObject:@{
            @"name" : name,
            @"model" : [model isKindOfClass:NSString.class] ? model : @"",
            @"w" : @(MAX(WMIN, MIN(WMAX, [w intValue]))),
            @"h" : @(MAX(HMIN, MIN(HMAX, [h intValue])))
        }];
    }
    return out;
}

- (void)setPresets:(NSArray *)a {
    [self.ud setObject:a forKey:@"presets"];
    [self buildPresets];
}

- (void)load {
    _model = modelIndexByName([self.ud stringForKey:@"model"] ?: @"");
    if (_model < 0) {
        _model = DEFAULT_MODEL;
    }
    _w = (int)[self.ud integerForKey:@"w"] ?: kModels[_model].w;
    _h = (int)[self.ud integerForKey:@"h"] ?: kModels[_model].h;
    _w = MAX(WMIN, MIN(WMAX, _w));
    _h = MAX(HMIN, MIN(HMAX, _h));
    _ratio = (double)_h / _w;
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

// 盖在一行上的透明按钮：点一下执行 action
- (NSButton *)rowButtonAt:(CGFloat)y height:(CGFloat)h action:(SEL)a tag:(NSInteger)tag in:(NSView *)v {
    NSButton *b = [NSButton buttonWithTitle:@"" target:self action:a];
    b.bordered = NO;
    b.transparent = YES;
    b.tag = tag;
    b.frame = NSMakeRect(0, y, PANEL_W, h);
    [v addSubview:b];
    return b;
}

- (void)buildPanel {
    FlipView *r = [[FlipView alloc] initWithFrame:NSMakeRect(0, 0, PANEL_W, 100)];
    self.root = r;

    // 标题、状态和总开关
    NSTextField *t = label(@"远程模式", 15, NSFontWeightSemibold, NSColor.labelColor);
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
    rowTitle(r, y, @"antenna.radiowaves.left.and.right", NO, @"跟随 UU 远程");
    self.followUU = [NSSwitch new];
    self.followUU.controlSize = NSControlSizeSmall;
    [self.followUU sizeToFit];
    self.followUU.state = [self.ud objectForKey:@"followUU"] && ![self.ud boolForKey:@"followUU"] ? NSControlStateValueOff
                                                                                                   : NSControlStateValueOn;
    self.followUU.target = self;
    self.followUU.action = @selector(followClicked:);
    self.followUU.toolTip = @"网易 UU 远程连上时自动开启远程画面，断开时自动关闭";
    placeRight(r, y, self.followUU, 0);

    // 机型：按品牌、系列分层的菜单
    y += ROW_H;
    rowTitle(r, y, @"iphone", NO, @"机型");
    self.modelBtn = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 180, 24) pullsDown:YES];
    self.modelBtn.bordered = NO;
    self.modelBtn.alignment = NSTextAlignmentRight;
    self.modelBtn.menu.delegate = self;
    placeRight(r, y, self.modelBtn, -4);

    // 显示大小：标题行右侧是分辨率和相对机型推荐宽度的比例，下面一整条滑块，两端写方向
    y += ROW_H;
    rowTitle(r, y, @"textformat.size", NO, @"显示大小");
    self.sizeLabel = numLabel(150);
    placeRight(r, y, self.sizeLabel, 0);
    self.slider = [NSSlider sliderWithValue:WMIN minValue:WMIN maxValue:WMAX target:self action:@selector(slid:)];
    self.slider.frame = NSMakeRect(PAD - 2, y + 40, PANEL_W - PAD * 2 + 4, 24);
    self.slider.numberOfTickMarks = 7;
    [r addSubview:self.slider];
    NSTextField *l = label(@"更大文本", 11, NSFontWeightRegular, NSColor.secondaryLabelColor);
    [l setFrameOrigin:NSMakePoint(PAD, y + 66)];
    [r addSubview:l];
    NSTextField *m = label(@"更多空间", 11, NSFontWeightRegular, NSColor.secondaryLabelColor);
    [m setFrameOrigin:NSMakePoint(PANEL_W - PAD - m.frame.size.width, y + 66)];
    [r addSubview:m];

    // 画面高度：数字加「− | +」，每点一下 ±10
    y += SIZE_H;
    rowTitle(r, y, @"arrow.up.and.down", NO, @"画面高度");
    self.heightSeg = [NSSegmentedControl
        segmentedControlWithImages:@[
            [NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:@"调矮"],
            [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"调高"]
        ]
                      trackingMode:NSSegmentSwitchTrackingMomentary
                            target:self
                            action:@selector(stepped:)];
    [self.heightSeg setWidth:30 forSegment:0];
    [self.heightSeg setWidth:30 forSegment:1];
    [self.heightSeg sizeToFit];
    self.heightSeg.toolTip = @"只改高度。画面底部被输入法挡住时调矮";
    placeRight(r, y, self.heightSeg, -2);
    self.heightLabel = numLabel(60);
    placeRight(r, y, self.heightLabel, self.heightSeg.frame.size.width + 6);
    y += ROW_H + 6;
    separator(r, y);

    // 预设区：标题、各条预设、新建预设、退出。条数会变，放进单独的容器里重排
    self.presetBox = [[FlipView alloc] initWithFrame:NSMakeRect(0, y + 1, PANEL_W, 10)];
    [r addSubview:self.presetBox];

    NSViewController *vc = [NSViewController new];
    vc.view = r;
    self.popover = [NSPopover new];
    self.popover.contentViewController = vc;
    self.popover.behavior = NSPopoverBehaviorTransient;
    [self buildPresets];
}

// 重排预设区，面板高度跟着变。tag：100 起是各条预设的勾，99 是新建预设
- (void)buildPresets {
    FlipView *b = self.presetBox;
    for (NSView *v in [b.subviews copy]) {
        [v removeFromSuperview];
    }
    NSTextField *h = label(@"预设", 12, NSFontWeightMedium, NSColor.secondaryLabelColor);
    [h setFrameOrigin:NSMakePoint(PAD, 10)];
    [b addSubview:h];
    CGFloat y = 30;
    NSArray *ps = self.presets;
    for (NSInteger i = 0; i < (NSInteger)ps.count; i++) {
        NSImageView *ck = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"checkmark"
                                                                    accessibilityDescription:nil]];
        ck.contentTintColor = NSColor.controlAccentColor;
        ck.frame = NSMakeRect(PAD + 6, y + 8, 16, 16);
        ck.tag = 100 + i;
        [b addSubview:ck];
        NSTextField *n = label(ps[i][@"name"], 13, NSFontWeightRegular, NSColor.labelColor);
        n.lineBreakMode = NSLineBreakByTruncatingTail;
        n.frame = NSMakeRect(TITLE_X, y + 7, PANEL_W - TITLE_X - PAD - 90, 18);
        [b addSubview:n];
        NSTextField *sz = numLabel(90);
        sz.stringValue = [NSString stringWithFormat:@"%@ × %@", ps[i][@"w"], ps[i][@"h"]];
        sz.frame = NSMakeRect(PANEL_W - PAD - 90, y + 8, 90, 17);
        [b addSubview:sz];
        NSButton *rb = [self rowButtonAt:y height:PRESET_H action:@selector(pickPreset:) tag:i in:b];
        NSMenu *menu = [NSMenu new];
        for (NSString *title in @[ @"用当前尺寸覆盖", @"删除" ]) {
            NSMenuItem *it = [menu addItemWithTitle:title
                                             action:[title isEqualToString:@"删除"] ? @selector(deletePreset:)
                                                                                     : @selector(overwritePreset:)
                                      keyEquivalent:@""];
            it.target = self;
            it.tag = i;
        }
        rb.menu = menu;
        rb.toolTip = @"点一下切换，右键可覆盖或删除";
        y += PRESET_H;
    }
    // 新建预设：自动起名，当前尺寸已经存过时变灰
    y -= 4;
    rowTitle(b, y, @"plus", YES, @"新建预设").tag = 99;
    [self rowButtonAt:y height:ROW_H action:@selector(addPreset:) tag:99 in:b];
    y += ROW_H + 2;
    separator(b, y);
    NSTextField *q = label(@"退出", 13, NSFontWeightRegular, NSColor.labelColor);
    [q setFrameOrigin:NSMakePoint(PAD, y + 10)];
    [b addSubview:q];
    NSButton *qb = [self rowButtonAt:y height:38 action:@selector(terminate:) tag:0 in:b];
    qb.target = NSApp;
    y += 42;

    b.frame = NSMakeRect(0, b.frame.origin.y, PANEL_W, y);
    NSRect f = self.root.frame;
    f.size.height = NSMaxY(b.frame);
    self.root.frame = f;
    self.popover.contentSize = f.size;
    [self refresh];
}

// 显示大小能拖到的宽度：比例不变时高度也要在允许范围内
- (void)sliderRange:(double *)lo hi:(double *)hi {
    *lo = MAX(WMIN, ceil(HMIN / _ratio));
    *hi = MIN(WMAX, floor(HMAX / _ratio));
}

- (void)refresh {
    // 等 Crisp 这类工具退出的那几秒也算「正在开启」
    BOOL waiting = otherAppsQuitting();
    BOOL on = displayIsOn() || waiting, closing = displayIsClosing(), mirrored = displayIsMirrored();
    BOOL ready = on && mirrored && !closing;
    self.power.state = on && !closing ? NSControlStateValueOn : NSControlStateValueOff;
    self.power.enabled = !closing && !waiting && !_terminating;
    NSString *st = closing ? @"正在关闭" : !on ? @"已关闭" : ready ? @"已开启" : @"正在开启";
    self.stateLabel.stringValue = ready ? [NSString stringWithFormat:@"%@ · %d × %d", st, _w, _h] : st;
    self.stateLabel.textColor = ready ? NSColor.controlAccentColor : NSColor.secondaryLabelColor;
    self.statusItem.button.image = statusImage(on);

    [self.modelBtn.menu removeAllItems];
    [self.modelBtn addItemWithTitle:@(kModels[_model].name)];
    [self.modelBtn sizeToFit];
    NSRect f = self.modelBtn.frame;
    CGFloat w = MIN(f.size.width, PANEL_W - TITLE_X - 70);
    self.modelBtn.frame = NSMakeRect(PANEL_W - PAD + 4 - w, f.origin.y, w, f.size.height);

    // 比例：相对机型推荐宽度，越大一屏放的内容越多
    self.sizeLabel.stringValue =
        [NSString stringWithFormat:@"%d × %d · %ld%%", _w, _h, lround(_w * 100.0 / kModels[_model].w)];
    double lo, hi;
    [self sliderRange:&lo hi:&hi];
    self.slider.minValue = lo;
    self.slider.maxValue = hi;
    self.slider.doubleValue = _w;
    self.heightLabel.stringValue = [NSString stringWithFormat:@"%d", _h];

    NSInteger match = [self matchingPreset];
    for (NSView *v in self.presetBox.subviews) {
        if (v.tag >= 100) {
            v.hidden = v.tag - 100 != match;
        } else if (v.tag == 99 && [v isKindOfClass:NSButton.class]) {
            ((NSButton *)v).enabled = match < 0;
        } else if (v.tag == 99) {
            ((NSTextField *)v).textColor = match < 0 ? NSColor.labelColor : NSColor.tertiaryLabelColor;
        }
    }
}

#pragma mark 机型菜单

// 机型项右侧带推荐尺寸
- (void)addModel:(int)i to:(NSMenu *)m {
    NSMenuItem *it = [m addItemWithTitle:@(kModels[i].name) action:@selector(pickModel:) keyEquivalent:@""];
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
                                   initWithString:[NSString stringWithFormat:@"\t%d × %d", kModels[i].w, kModels[i].h]
                                       attributes:@{
                                           NSFontAttributeName : [NSFont monospacedDigitSystemFontOfSize:f.pointSize - 1
                                                                                                 weight:NSFontWeightRegular],
                                           NSForegroundColorAttributeName : NSColor.secondaryLabelColor,
                                           NSParagraphStyleAttributeName : ps
                                       }]];
    it.attributedTitle = as;
}

// 点开机型菜单时现搭：第一项是按钮标题，然后每个品牌一个子菜单，有系列的（iPhone 按代）再分一层
- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    [menu addItemWithTitle:@(kModels[_model].name) action:nil keyEquivalent:@""];
    for (NSString *g in groupNames()) {
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
                NSMenuItem *si = [gm addItemWithTitle:@(kModels[i].series) action:nil keyEquivalent:@""];
                si.submenu = sub;
                BOOL cur = kModels[_model].series && strcmp(kModels[_model].series, kModels[i].series) == 0;
                si.state = cur ? NSControlStateValueOn : NSControlStateValueOff;
            }
            [self addModel:i to:sub];
        }
        NSMenuItem *gi = [menu addItemWithTitle:g action:nil keyEquivalent:@""];
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
    _w = MAX(WMIN, MIN(WMAX, w));
    _h = MAX(HMIN, MIN(HMAX, h));
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
    displayResize(_w, _h);
    [self save];
}

// 换一整套尺寸（机型、预设）：比例跟着换
- (void)useW:(int)w h:(int)h {
    _ratio = (double)MAX(HMIN, MIN(HMAX, h)) / MAX(WMIN, MIN(WMAX, w));
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
    int h = MAX(HMIN, MIN(HMAX, _h + d * STEP));
    _ratio = (double)h / _w;
    [self setW:_w h:h];
}

- (void)pickModel:(NSMenuItem *)it {
    if (it.tag < 0 || it.tag >= NMODEL) {
        return;
    }
    _model = (int)it.tag;
    [self useW:kModels[_model].w h:kModels[_model].h];
}

- (void)pickPreset:(NSButton *)b {
    NSArray *ps = self.presets;
    if (b.tag >= (NSInteger)ps.count) {
        return;
    }
    NSDictionary *d = ps[b.tag];
    int mi = modelIndexByName(d[@"model"]);
    if (mi >= 0) {
        _model = mi;
    }
    [self useW:[d[@"w"] intValue] h:[d[@"h"] intValue]];
}

// 新建预设不用输入：名字是机型加尺寸
- (void)addPreset:(id)s {
    if ([self matchingPreset] >= 0) {
        return;
    }
    NSMutableArray *ps = [self.presets mutableCopy];
    [ps addObject:@{
        @"name" : [NSString stringWithFormat:@"%s %d×%d", kModels[_model].name, _w, _h],
        @"model" : @(kModels[_model].name),
        @"w" : @(_w),
        @"h" : @(_h)
    }];
    [self setPresets:ps];
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
    if (!displayOn(_w, _h)) {
        otherAppsRelaunch();
        NSAlert *a = [NSAlert new];
        a.messageText = @"虚拟屏创建失败";
        a.informativeText = @"需要 macOS 12 或更新的版本。";
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
        if (++_rebuilds > 3 || !displayOn(_w, _h)) {
            displayAbandon();
        }
    }
    // 虚拟屏放弃重建，或者排列一直被改掉而自动关闭了：远程画面已经关掉，把让出来的工具打开
    if (!displayIsOn() && !displayIsClosing() && !otherAppsQuitting() && !_terminating) {
        otherAppsRelaunch();
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
                              [p moveToPoint:NSMakePoint(4.5, 7.5)];
                              [p lineToPoint:NSMakePoint(8, 11)];
                              [p lineToPoint:NSMakePoint(10, 7)];
                              [p lineToPoint:NSMakePoint(13.5, 10.5)];
                              p.lineWidth = 1.8;
                              p.lineCapStyle = NSLineCapStyleRound;
                              p.lineJoinStyle = NSLineJoinStyleRound;
                              [NSColor.blackColor set];
                              if (on) {
                                  [RR(NSMakeRect(1, 2, 16, 14), 4) fill];
                                  [NSGraphicsContext.currentContext setCompositingOperation:NSCompositingOperationClear];
                              } else {
                                  NSBezierPath *box = RR(NSMakeRect(1.5, 2.5, 15, 13), 3.5);
                                  box.lineWidth = 1;
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
}

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    [self load];
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.toolTip = @"远程模式";
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
    // 打开时不自动开远程画面。上次被强杀或崩溃时物理屏没恢复、让出来的工具也没打开：这里补上
    displayRecoverFromCrash();
    displayStartTracking();
    otherAppsRelaunch();
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
