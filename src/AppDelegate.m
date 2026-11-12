#import "AppDelegate.h"
#import "Card.h"
#import "DisplayControl.h"
#import "MenuButton.h"
#import "PhoneModels.h"
#import "PillButton.h"
#import "PowerButton.h"
#import "SegmentView.h"
#import "StepperView.h"
#import "Theme.h"

@interface AppDelegate ()
@property(strong) NSWindow *win;
@property(strong) Flipped *root, *pillBox;
@property(strong) PowerButton *power;
@property(strong) NSTextField *stateLabel, *wField, *hField;
@property(strong) SegmentView *brandSeg;
@property(strong) MenuButton *modelBtn;
@property(strong) StepperView *wStep, *hStep;
@property(strong) NSPopover *namePop;
@property(strong) NSTextField *nameField;
@property(copy) void (^nameDone)(NSString *);
@property(strong) id<NSObject> activity;
@end

@implementation AppDelegate {
    int _model, _w, _h, _menuGroup, _rebuilds;
    BOOL _terminating;
    CFAbsoluteTime _rebuildT0;
}

#define WIN_W 440
#define PAD 24
#define ROW_H 44
#define CARD_TOP 216
#define PILLS_TOP (CARD_TOP + ROW_H * 4 + 48)
#define SEG_W 78        // 品牌分段每格宽度
#define SERIES_TAG 1000 // 型号菜单里「xx 系列」子菜单项的 tag 起点

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
}

- (void)save {
    [self.ud setObject:@(kModels[_model].name) forKey:@"model"];
    [self.ud setInteger:_w forKey:@"w"];
    [self.ud setInteger:_h forKey:@"h"];
}

#pragma mark 界面

- (NSTextField *)label:(NSString *)s size:(CGFloat)sz weight:(NSFontWeight)wt color:(NSColor *)c {
    NSTextField *t = [NSTextField labelWithString:s];
    t.font = [NSFont systemFontOfSize:sz weight:wt];
    t.textColor = c;
    [t sizeToFit];
    return t;
}

- (NSImageView *)icon:(NSString *)sym size:(CGFloat)pt tint:(NSColor *)tint center:(NSPoint)c in:(NSView *)v {
    NSImageView *iv = [NSImageView imageViewWithImage:Sym(sym, pt, NSFontWeightRegular, nil)];
    iv.contentTintColor = tint;
    iv.frame = NSMakeRect(c.x - 12, c.y - 12, 24, 24);
    [v addSubview:iv];
    return iv;
}

// 卡片里的一行：左侧主题色线性图标加标题
- (void)row:(int)i in:(Card *)card symbol:(NSString *)sym title:(NSString *)title {
    [self icon:sym size:14 tint:ThemeInk() center:NSMakePoint(28, i * ROW_H + ROW_H / 2) in:card];
    NSTextField *t = [self label:title size:13 weight:NSFontWeightRegular color:NSColor.labelColor];
    [t setFrameOrigin:NSMakePoint(48, i * ROW_H + floor((ROW_H - t.frame.size.height) / 2))];
    [card addSubview:t];
}

- (StepperView *)stepperRow:(int)i in:(Card *)card horizontal:(BOOL)horiz {
    StepperView *s = [[StepperView alloc]
        initWithFrame:NSMakeRect(card.frame.size.width - 12 - 136, i * ROW_H + (ROW_H - 28) / 2, 136, 28)];
    s.field.delegate = self;
    s.field.target = self;
    s.field.action = @selector(typed:);
    __weak AppDelegate *me = self;
    s.onStep = ^(int d) {
        [me stepW:horiz ? d : 0 h:horiz ? 0 : d];
    };
    [card addSubview:s];
    return s;
}

- (void)buildWindow {
    CGFloat H0 = PILLS_TOP + 28 + PAD;
    self.win =
        [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, WIN_W, H0)
                                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                              NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskFullSizeContentView
                                      backing:NSBackingStoreBuffered
                                        defer:NO];
    self.win.titlebarAppearsTransparent = YES;
    self.win.titleVisibility = NSWindowTitleHidden;
    self.win.title = @"远程模式";
    self.win.releasedWhenClosed = NO;
    self.win.delegate = self;
    self.win.movableByWindowBackground = YES;
    self.win.backgroundColor = Backdrop();
    self.root = [[Flipped alloc] initWithFrame:NSMakeRect(0, 0, WIN_W, H0)];
    self.win.contentView = self.root;
    Flipped *root = self.root;
    CGFloat cw = WIN_W - PAD * 2;

    // 总开关：大圆按钮加一行状态
    self.power = [[PowerButton alloc] initWithFrame:NSMakeRect((WIN_W - 176) / 2, 12, 176, 176)];
    self.power.target = self;
    self.power.action = @selector(powerClicked:);
    [root addSubview:self.power];
    self.stateLabel = [self label:@"远程模式已开启" size:13 weight:NSFontWeightMedium color:NSColor.labelColor];
    self.stateLabel.alignment = NSTextAlignmentCenter;
    self.stateLabel.frame = NSMakeRect(0, 176, WIN_W, 18);
    [root addSubview:self.stateLabel];

    // 品牌、型号、宽、高
    Card *card = [[Card alloc] initWithFrame:NSMakeRect(PAD, CARD_TOP, cw, ROW_H * 4)];
    card.rows = 4;
    card.rowH = ROW_H;
    [root addSubview:card];
    [self row:0 in:card symbol:@"tag" title:@"品牌"];
    NSArray *groups = groupNames();
    self.brandSeg = [[SegmentView alloc]
        initWithFrame:NSMakeRect(cw - 12 - SEG_W * groups.count, (ROW_H - 28) / 2, SEG_W * groups.count, 28)];
    self.brandSeg.titles = groups;
    __weak AppDelegate *me = self;
    self.brandSeg.onPick = ^(NSInteger g) {
        [me pickBrand:g];
    };
    [card addSubview:self.brandSeg];
    [self row:1 in:card symbol:@"iphone" title:@"型号"];
    self.modelBtn = [[MenuButton alloc] initWithFrame:NSMakeRect(88, ROW_H + (ROW_H - 28) / 2, cw - 88 - 6, 28)];
    [card addSubview:self.modelBtn];
    [self row:2 in:card symbol:@"arrow.left.and.right" title:@"宽度"];
    self.wStep = [self stepperRow:2 in:card horizontal:YES];
    self.wField = self.wStep.field;
    [self row:3 in:card symbol:@"arrow.up.and.down" title:@"高度"];
    self.hStep = [self stepperRow:3 in:card horizontal:NO];
    self.hField = self.hStep.field;

    // 预设
    [self icon:@"bookmark"
          size:11
          tint:NSColor.secondaryLabelColor
        center:NSMakePoint(PAD + 8, PILLS_TOP - 16)
            in:root];
    NSTextField *pl = [self label:@"预设" size:12 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
    [pl setFrameOrigin:NSMakePoint(PAD + 20, PILLS_TOP - 16 - floor(pl.frame.size.height / 2))];
    [root addSubview:pl];
    self.pillBox = [[Flipped alloc] initWithFrame:NSMakeRect(PAD, PILLS_TOP, cw, 28)];
    [root addSubview:self.pillBox];
    _menuGroup = -1;
}

// 型号菜单只列当前品牌的型号，每项右侧带推荐尺寸。iPhone 按代放进子菜单
- (NSMenuItem *)modelItem:(int)i title:(NSString *)t {
    NSFont *f = [NSFont menuFontOfSize:0], *nf = [NSFont monospacedDigitSystemFontOfSize:f.pointSize - 1
                                                                                  weight:NSFontWeightRegular];
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.tabStops = @[ [[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentRight location:220 options:@{}] ];
    NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:t action:@selector(pickModel:) keyEquivalent:@""];
    it.target = self;
    it.tag = i;
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc]
        initWithString:t
            attributes:@{NSFontAttributeName : f, NSParagraphStyleAttributeName : ps}];
    [as appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:[NSString stringWithFormat:@"\t%d × %d", kModels[i].w, kModels[i].h]
                                       attributes:@{
                                           NSFontAttributeName : nf,
                                           NSForegroundColorAttributeName : NSColor.secondaryLabelColor,
                                           NSParagraphStyleAttributeName : ps
                                       }]];
    it.attributedTitle = as;
    return it;
}

- (void)buildModelMenuForGroup:(int)g {
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    NSString *gn = groupNames()[g];
    NSMenu *sub = nil;
    for (int i = 0; i < NMODEL; i++) {
        if (![gn isEqualToString:@(kModels[i].group)]) {
            continue;
        }
        NSString *name = @(kModels[i].name);
        if (!kModels[i].series) {
            [menu addItem:[self modelItem:i title:name]];
            continue;
        }
        if (i == 0 || !kModels[i - 1].series || strcmp(kModels[i - 1].series, kModels[i].series) != 0) {
            NSMenuItem *si = [[NSMenuItem alloc] initWithTitle:@(kModels[i].series) action:nil keyEquivalent:@""];
            si.tag = SERIES_TAG + i;
            sub = [NSMenu new];
            sub.autoenablesItems = NO;
            si.submenu = sub;
            [menu addItem:si];
        }
        [sub addItem:[self modelItem:i title:name]];
    }
    self.modelBtn.list = menu;
    _menuGroup = g;
}

- (BOOL)presetIsCurrent:(NSDictionary *)d {
    return modelIndexByName(d[@"model"]) == _model && [d[@"w"] intValue] == _w && [d[@"h"] intValue] == _h;
}

- (NSMenuItem *)item:(NSString *)t symbol:(NSString *)sym action:(SEL)a tag:(NSInteger)tag in:(NSMenu *)m {
    NSMenuItem *it = [m addItemWithTitle:t action:a keyEquivalent:@""];
    it.target = self;
    it.tag = tag;
    it.image = [NSImage imageWithSystemSymbolName:sym accessibilityDescription:nil];
    return it;
}

- (void)buildPills {
    for (NSView *v in [self.pillBox.subviews copy]) {
        [v removeFromSuperview];
    }
    NSArray *ps = self.presets;
    for (NSInteger i = 0; i <= (NSInteger)ps.count; i++) {
        BOOL add = (i == (NSInteger)ps.count);
        PillButton *p = [[PillButton alloc] initWithFrame:NSMakeRect(0, 0, 60, 28)];
        p.index = i;
        p.target = self;
        if (add) {
            p.title = @"存为预设";
            p.symbol = @"plus";
            p.style = PB_ADD;
            p.action = @selector(addPreset:);
        } else {
            p.title = ps[i][@"name"];
            p.action = @selector(pickPreset:);
            p.toolTip = [NSString stringWithFormat:@"%@ × %@", ps[i][@"w"], ps[i][@"h"]];
            NSMenu *m = [NSMenu new];
            [self item:@"改名…" symbol:@"pencil" action:@selector(renamePreset:) tag:i in:m];
            [self item:@"用当前尺寸覆盖"
                symbol:@"arrow.triangle.2.circlepath"
                action:@selector(overwritePreset:)
                   tag:i
                    in:m];
            [m addItem:[NSMenuItem separatorItem]];
            [self item:@"删除" symbol:@"trash" action:@selector(deletePreset:) tag:i in:m];
            p.contextMenu = m;
        }
        [self.pillBox addSubview:p];
    }
}

// 排预设按钮，放不下就换行；行数变了窗口跟着变高
- (void)layoutPills {
    CGFloat x = 0, y = 0, cw = self.pillBox.frame.size.width, h = 28, gap = 8;
    for (PillButton *p in self.pillBox.subviews) {
        CGFloat w = MIN(cw, [p fitWidth]);
        if (x > 0 && x + w > cw) {
            x = 0;
            y += h + gap;
        }
        p.frame = NSMakeRect(x, y, w, h);
        x += w + gap;
    }
    CGFloat boxH = y + h;
    self.pillBox.frame = NSMakeRect(PAD, PILLS_TOP, cw, boxH);
    CGFloat H = PILLS_TOP + boxH + PAD;
    NSRect f = self.win.frame;
    NSRect cr = [self.win contentRectForFrameRect:f];
    CGFloat dy = H - cr.size.height;
    if (dy != 0) {
        f.origin.y -= dy;
        f.size.height += dy;
        [self.win setFrame:f display:YES animate:self.win.visible];
    }
}

- (void)refresh {
    const Model *m = &kModels[_model];
    BOOL on = displayIsOn(), closing = displayIsClosing(), mirrored = displayIsMirrored();
    // 总开关
    [self.power setOn:on animated:self.win.visible];
    self.power.busy = closing;
    self.stateLabel.stringValue = closing ? @"正在关闭" : !on ? @"已关闭" : mirrored ? @"远程模式已开启" : @"正在开启";
    self.stateLabel.textColor = (on && mirrored) ? ThemeInk() : NSColor.secondaryLabelColor;
    // 品牌和型号联动
    int g = groupOfModel(_model);
    self.brandSeg.selected = g;
    if (g != _menuGroup) {
        [self buildModelMenuForGroup:g];
    }
    self.modelBtn.title = @(m->name);
    self.modelBtn.selectedTag = _model;
    for (NSMenuItem *it in self.modelBtn.list.itemArray) {
        BOOL hit = it.tag == _model;
        for (NSMenuItem *c in it.submenu.itemArray) {
            c.state = (c.tag == _model) ? NSControlStateValueOn : NSControlStateValueOff;
            if (c.tag == _model) {
                hit = YES;
                self.modelBtn.selectedTag = it.tag;
            }
        }
        it.state = hit ? NSControlStateValueOn : NSControlStateValueOff;
    }
    CGFloat cardW = self.modelBtn.superview.frame.size.width, bw = [self.modelBtn fitWidthMax:cardW - 88 - 6];
    self.modelBtn.frame = NSMakeRect(cardW - 6 - bw, ROW_H + (ROW_H - 28) / 2, bw, 28);
    // 宽高
    [self syncField:self.wField value:_w];
    [self syncField:self.hField value:_h];
    self.wStep.canMinus = _w > WMIN;
    self.wStep.canPlus = _w < WMAX;
    self.hStep.canMinus = _h > HMIN;
    self.hStep.canPlus = _h < HMAX;
    // 预设：当前这条高亮并带下拉箭头；当前尺寸已经存过时「存为预设」变淡
    NSArray *presets = self.presets;
    BOOL saved = NO;
    for (PillButton *p in self.pillBox.subviews) {
        if (p.style == PB_ADD) {
            continue;
        }
        BOOL cur = p.index < (NSInteger)presets.count && [self presetIsCurrent:presets[p.index]];
        saved |= cur;
        p.style = cur ? PB_SELECTED : PB_PLAIN;
        p.trailing = cur ? @"chevron.down" : nil;
        [p setNeedsDisplay:YES];
    }
    for (PillButton *p in self.pillBox.subviews) {
        if (p.style == PB_ADD) {
            p.dimmed = saved;
            p.alphaValue = saved ? 0.35 : 1;
        }
    }
    [self layoutPills];
}

#pragma mark 操作

- (void)setW:(int)w h:(int)h {
    _w = MAX(WMIN, MIN(WMAX, w));
    _h = MAX(HMIN, MIN(HMAX, h));
    [self refresh];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyNow) object:nil];
    [self performSelector:@selector(applyNow) withObject:nil afterDelay:0.25];
}

- (void)stepW:(int)dw h:(int)dh {
    [self.win makeFirstResponder:nil];
    [self setW:_w + dw * STEP h:_h + dh * STEP];
}

- (void)applyNow {
    displayResize(_w, _h);
    [self save];
}

// 把输入框显示的数字对齐到实际值；正在编辑时改编辑器里的文字，免得留下一个超范围的数
- (void)syncField:(NSTextField *)f value:(int)v {
    NSString *str = [NSString stringWithFormat:@"%d", v];
    NSText *ed = f.currentEditor;
    if (ed) {
        if (![ed.string isEqualToString:str]) {
            ed.string = str;
            [ed selectAll:nil];
        }
    } else {
        f.intValue = v;
    }
}

// 输入为空或不是正数时恢复原值
- (void)typed:(NSTextField *)f {
    int v = f.intValue;
    if (v <= 0) {
        v = (f == self.wField) ? _w : _h;
    }
    if (f == self.wField) {
        [self setW:v h:_h];
    } else {
        [self setW:_w h:v];
    }
    // 结束编辑时控件会把输入的原文写回，等它写完再对齐一次
    dispatch_async(dispatch_get_main_queue(), ^{
        [self syncField:self.wField value:self->_w];
        [self syncField:self.hField value:self->_h];
    });
}

// 输入了非数字也允许结束编辑，随后由 typed: 恢复原值
- (BOOL)control:(NSControl *)c didFailToFormatString:(NSString *)str errorDescription:(NSString *)e {
    return YES;
}

// 输入框里按上下方向键也走一步
- (BOOL)control:(NSControl *)c textView:(NSTextView *)tv doCommandBySelector:(SEL)s {
    int d = s == @selector(moveUp:) ? 1 : s == @selector(moveDown:) ? -1 : 0;
    if (!d || (c != self.wField && c != self.hField)) {
        return NO;
    }
    int v = tv.string.intValue + d * STEP;
    if (c == self.wField) {
        [self setW:v h:_h];
    } else {
        [self setW:_w h:v];
    }
    return YES;
}

// 切品牌：自动选中该品牌第一个型号并套用推荐尺寸
- (void)pickBrand:(NSInteger)g {
    if (g == groupOfModel(_model)) {
        return;
    }
    [self.win makeFirstResponder:nil];
    _model = firstModelOfGroup((int)g);
    [self setW:kModels[_model].w h:kModels[_model].h];
}

- (void)pickModel:(NSMenuItem *)it {
    if (it.tag < 0 || it.tag >= NMODEL) {
        return;
    }
    _model = (int)it.tag;
    [self setW:kModels[_model].w h:kModels[_model].h];
}

// 开或关远程画面（窗口按钮和 Dock 菜单共用）。关闭是异步的，期间按钮显示「正在关闭」并且不接受点击
- (void)setRemoteOn:(BOOL)on {
    if (displayIsClosing() || _terminating) {
        return;
    }
    if (on) {
        if (!displayOn(_w, _h)) {
            NSAlert *a = [NSAlert new];
            a.messageText = @"虚拟屏创建失败";
            a.informativeText = @"需要 macOS 12 或更新的版本。";
            [a runModal];
        }
    } else {
        displayOff(^{
            [self refresh];
        });
    }
    [self refresh];
}

- (void)powerClicked:(id)s {
    [self setRemoteOn:!displayIsOn()];
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
    [self refresh];
}

- (void)didWake:(NSNotification *)n {
    displayScheduleVerify();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        displayScheduleVerify();
    });
}

// 在按钮旁弹出小气泡输入名称，回车确认
- (void)askNameFrom:(NSView *)anchor initial:(NSString *)init done:(void (^)(NSString *))done {
    [self.namePop close];
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 250, 48)];
    NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 12, 180, 24)];
    tf.stringValue = init;
    tf.placeholderString = @"预设名称";
    tf.bezelStyle = NSTextFieldRoundedBezel;
    tf.focusRingType = NSFocusRingTypeNone;
    tf.target = self;
    tf.action = @selector(nameOK:);
    tf.cell.sendsActionOnEndEditing = NO;
    [v addSubview:tf];
    NSButton *ok = [NSButton buttonWithImage:Sym(@"checkmark", 12, NSFontWeightSemibold, NSColor.whiteColor)
                                      target:self
                                      action:@selector(nameOK:)];
    ok.bezelStyle = NSBezelStyleRounded;
    ok.keyEquivalent = @"\r";
    ok.bezelColor = ThemeA(1);
    ok.contentTintColor = NSColor.whiteColor;
    ok.frame = NSMakeRect(194, 7, 50, 32);
    [v addSubview:ok];
    NSViewController *vc = [NSViewController new];
    vc.view = v;
    NSPopover *pop = [NSPopover new];
    pop.contentViewController = vc;
    pop.behavior = NSPopoverBehaviorTransient;
    pop.contentSize = v.frame.size;
    self.namePop = pop;
    self.nameField = tf;
    self.nameDone = done;
    [pop showRelativeToRect:anchor.bounds ofView:anchor preferredEdge:NSRectEdgeMaxY];
    [v.window makeFirstResponder:tf];
}

- (void)nameOK:(id)s {
    NSString *n = [self.nameField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!n.length) {
        NSBeep();
        return;
    }
    void (^done)(NSString *) = self.nameDone;
    self.nameDone = nil;
    [self.namePop close];
    self.namePop = nil;
    if (done) {
        done(n);
    }
}

- (PillButton *)pillAt:(NSInteger)i {
    for (PillButton *p in self.pillBox.subviews) {
        if (p.index == i) {
            return p;
        }
    }
    return nil;
}

- (void)addPreset:(PillButton *)s {
    NSString *mn = @(kModels[_model].name);
    [self askNameFrom:s
              initial:mn
                 done:^(NSString *n) {
                     NSMutableArray *ps = [self.presets mutableCopy];
                     [ps addObject:@{
                         @"name" : n,
                         @"model" : @(kModels[self->_model].name),
                         @"w" : @(self->_w),
                         @"h" : @(self->_h)
                     }];
                     [self setPresets:ps];
                     [self buildPills];
                     [self refresh];
                 }];
}

// 点未选中的预设是切换；点当前这条弹出改名、覆盖、删除
- (void)pickPreset:(PillButton *)p {
    if (p.style == PB_SELECTED) {
        [p popMenu];
        return;
    }
    NSArray *ps = self.presets;
    if (p.index >= (NSInteger)ps.count) {
        return;
    }
    NSDictionary *d = ps[p.index];
    int mi = modelIndexByName(d[@"model"]);
    if (mi >= 0) {
        _model = mi;
    }
    [self.win makeFirstResponder:nil];
    [self setW:[d[@"w"] intValue] h:[d[@"h"] intValue]];
}

- (void)renamePreset:(NSMenuItem *)it {
    NSInteger i = it.tag;
    if (i >= (NSInteger)self.presets.count) {
        return;
    }
    [self askNameFrom:[self pillAt:i] ?: self.pillBox
              initial:self.presets[i][@"name"]
                 done:^(NSString *n) {
                     NSMutableArray *ps = [self.presets mutableCopy];
                     if (i >= (NSInteger)ps.count) {
                         return;
                     }
                     NSMutableDictionary *d = [ps[i] mutableCopy];
                     d[@"name"] = n;
                     ps[i] = d;
                     [self setPresets:ps];
                     [self buildPills];
                     [self refresh];
                 }];
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
    [self refresh];
}

- (void)deletePreset:(NSMenuItem *)it {
    NSMutableArray *ps = [self.presets mutableCopy];
    if (it.tag >= (NSInteger)ps.count) {
        return;
    }
    [ps removeObjectAtIndex:it.tag];
    [self setPresets:ps];
    [self buildPills];
    [self refresh];
}

#pragma mark 应用生命周期

- (void)showWindow:(id)sender {
    [self.win makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)dockPreset:(NSMenuItem *)it {
    NSArray *ps = self.presets;
    if (it.tag >= (NSInteger)ps.count) {
        return;
    }
    NSDictionary *d = ps[it.tag];
    int mi = modelIndexByName(d[@"model"]);
    if (mi >= 0) {
        _model = mi;
    }
    [self setW:[d[@"w"] intValue] h:[d[@"h"] intValue]];
}

- (void)dockToggle:(id)sender {
    [self setRemoteOn:!displayIsOn()];
}

- (void)buildMainMenu {
    NSMenu *bar = [NSMenu new];
    NSMenuItem *appItem = [NSMenuItem new];
    [bar addItem:appItem];
    NSMenu *am = [NSMenu new];
    [am addItemWithTitle:@"打开设置" action:@selector(showWindow:) keyEquivalent:@","];
    [am addItem:[NSMenuItem separatorItem]];
    [am addItemWithTitle:@"隐藏远程模式" action:@selector(hide:) keyEquivalent:@"h"];
    [am addItemWithTitle:@"退出远程模式" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = am;
    NSMenuItem *editItem = [NSMenuItem new];
    [bar addItem:editItem];
    NSMenu *em = [[NSMenu alloc] initWithTitle:@"编辑"];
    [em addItemWithTitle:@"撤销" action:@selector(undo:) keyEquivalent:@"z"];
    [em addItem:[NSMenuItem separatorItem]];
    [em addItemWithTitle:@"剪切" action:@selector(cut:) keyEquivalent:@"x"];
    [em addItemWithTitle:@"拷贝" action:@selector(copy:) keyEquivalent:@"c"];
    [em addItemWithTitle:@"粘贴" action:@selector(paste:) keyEquivalent:@"v"];
    [em addItemWithTitle:@"全选" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = em;
    NSMenuItem *winItem = [NSMenuItem new];
    [bar addItem:winItem];
    NSMenu *wm = [[NSMenu alloc] initWithTitle:@"窗口"];
    [wm addItemWithTitle:@"关闭" action:@selector(performClose:) keyEquivalent:@"w"];
    [wm addItemWithTitle:@"最小化" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    winItem.submenu = wm;
    NSApp.mainMenu = bar;
}

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    [self load];
    [self buildMainMenu];
    [self buildWindow];
    [self buildPills];
    [self.win center];
    // 不让系统对本程序做 App Nap：窗口关掉后程序在后台，被降频的话定时器会晚很多，
    // 关闭时等虚拟屏下线、Dock 菜单切预设都靠定时器
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
    // 上次被强杀或崩溃时物理屏没恢复：先恢复，稍等显示器稳定再开虚拟屏
    if (displayRecoverFromCrash()) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            if (!self->_terminating) {
                displayOn(self->_w, self->_h);
                [self refresh];
            }
        });
    } else {
        displayOn(_w, _h);
    }
    [self refresh];
    [self showWindow:nil];
    [self.win makeFirstResponder:nil];
}

// 退出前先把显示器恢复好：恢复是异步的，这里先答复「稍后」，恢复完成再放行
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)s {
    [self save];
    if (_terminating) {
        return NSTerminateLater;
    }
    if (!displayIsOn() && !displayIsClosing()) {
        return NSTerminateNow;
    }
    _terminating = YES;
    displayOff(^{
        [NSApp replyToApplicationShouldTerminate:YES];
    });
    [self refresh];
    return NSTerminateLater;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)s {
    return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)s hasVisibleWindows:(BOOL)f {
    [self showWindow:nil];
    return NO;
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender {
    NSMenu *m = [NSMenu new];
    NSMenuItem *t = [[NSMenuItem alloc] initWithTitle:displayIsOn() ? @"关闭远程画面" : @"开启远程画面"
                                               action:@selector(dockToggle:)
                                        keyEquivalent:@""];
    t.target = self;
    [m addItem:t];
    NSArray *ps = self.presets;
    if (ps.count) {
        [m addItem:[NSMenuItem separatorItem]];
    }
    for (NSUInteger i = 0; i < ps.count; i++) {
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:ps[i][@"name"]
                                                    action:@selector(dockPreset:)
                                             keyEquivalent:@""];
        it.target = self;
        it.tag = i;
        it.state = [self presetIsCurrent:ps[i]] ? NSControlStateValueOn : NSControlStateValueOff;
        [m addItem:it];
    }
    return m;
}

- (void)applicationWillTerminate:(NSNotification *)n {
    [self save];
    displayOffSync();
}

@end
