#import "Rows.h"

@implementation ClickRow {
    BOOL _pressed;
}

// 面板在后台时第一下点击也直接生效，不用先点一下激活
- (BOOL)acceptsFirstMouse:(NSEvent *)e {
    return YES;
}

- (instancetype)initWithFrame:(NSRect)f {
    if ((self = [super initWithFrame:f])) {
        _enabled = YES;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

// 整行接收点击，里面的图标和文字不拦
- (NSView *)hitTest:(NSPoint)p {
    return NSPointInRect([self.superview convertPoint:p toView:self], self.bounds) ? self : nil;
}

- (void)setEnabled:(BOOL)e {
    _enabled = e;
    self.alphaValue = e ? 1 : 0.35;
}

- (void)drawRect:(NSRect)r {
    if (_pressed) {
        [[NSColor.labelColor colorWithAlphaComponent:0.06] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 6, 2) xRadius:8 yRadius:8] fill];
    }
}

- (void)mouseDown:(NSEvent *)e {
    if (!_enabled) {
        return;
    }
    _pressed = YES;
    self.needsDisplay = YES;
}

- (void)mouseUp:(NSEvent *)e {
    BOOL inside = NSPointInRect([self convertPoint:e.locationInWindow fromView:nil], self.bounds);
    BOOL fire = _pressed && inside;
    _pressed = NO;
    self.needsDisplay = YES;
    if (fire && self.onClick) {
        self.onClick();
    }
}

@end

@implementation PresetRow {
    NSImageView *_check;
    NSTextField *_name, *_detail;
    NSBox *_field; // 改名时垫在名字后面的输入框底和边框
    NSString *_saved;   // 开始改名时的名字，放弃时恢复
    NSRect _labelFrame; // 不编辑时名字的位置
    BOOL _editing, _cancel;
}

- (instancetype)initWithFrame:(NSRect)f name:(NSString *)name detail:(NSString *)detail {
    if (!(self = [super initWithFrame:f])) {
        return nil;
    }
    CGFloat h = f.size.height, w = f.size.width;
    _check = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"checkmark"
                                                       accessibilityDescription:nil]];
    _check.contentTintColor = NSColor.controlAccentColor;
    _check.frame = NSMakeRect(22, floor((h - 16) / 2), 16, 16);
    _check.hidden = YES;
    [self addSubview:_check];

    _detail = [NSTextField labelWithString:detail];
    _detail.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular];
    _detail.textColor = NSColor.secondaryLabelColor;
    _detail.alignment = NSTextAlignmentRight;
    _detail.frame = NSMakeRect(w - 16 - 90, floor((h - 17) / 2), 90, 17);
    [self addSubview:_detail];

    // 名字一直是同一个无边框输入框，位置和样式始终不变，改名时只打开编辑、显示后面那块底，文字不会挪动
    _labelFrame = NSMakeRect(52, floor((h - 18) / 2), w - 52 - 16 - 96, 18);
    _field = [[NSBox alloc] initWithFrame:NSInsetRect(_labelFrame, -6, -4)];
    _field.boxType = NSBoxCustom;
    _field.titlePosition = NSNoTitle;
    _field.cornerRadius = 6;
    _field.borderWidth = 1;
    _field.borderColor = NSColor.controlAccentColor;
    _field.fillColor = NSColor.textBackgroundColor;
    _field.hidden = YES;
    [self addSubview:_field];
    _name = [NSTextField textFieldWithString:name];
    _name.font = [NSFont systemFontOfSize:13];
    _name.bezeled = NO;
    _name.drawsBackground = NO;
    _name.focusRingType = NSFocusRingTypeNone;
    _name.lineBreakMode = NSLineBreakByTruncatingTail;
    _name.cell.scrollable = YES;
    _name.delegate = self;
    _name.frame = _labelFrame;
    [self addSubview:_name];
    [self showAsLabel];
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)e {
    return YES;
}

// 不在改名时整行接收点击（单击、双击、右键）；改名时交给输入框
- (NSView *)hitTest:(NSPoint)p {
    NSView *v = [super hitTest:p];
    return _editing || !v ? v : self;
}

- (void)setChecked:(BOOL)c {
    _checked = c;
    _check.hidden = !c;
}

- (void)showAsLabel {
    _name.editable = NO;
    _name.selectable = NO;
    _field.hidden = YES;
}

- (void)beginRename {
    if (_editing) {
        return;
    }
    _editing = YES;
    _cancel = NO;
    _saved = _name.stringValue;
    _name.editable = YES;
    _name.selectable = YES;
    _field.hidden = NO;
    // selectText: 会让输入框获得焦点并全选文字
    [_name selectText:nil];
}

- (void)mouseDown:(NSEvent *)e {
    if (_editing) {
        return;
    }
    if (e.clickCount >= 2) {
        [self beginRename];
    } else if (self.onPick) {
        self.onPick();
    }
}

// 回车、Esc 都由这里结束编辑。回车要自己结束：系统默认处理完回车会把文字重新选中，输入框还停在编辑中
- (BOOL)control:(NSControl *)c textView:(NSTextView *)tv doCommandBySelector:(SEL)sel {
    if (sel == @selector(cancelOperation:)) {
        _cancel = YES;
    } else if (sel != @selector(insertNewline:)) {
        return NO;
    }
    [self.window makeFirstResponder:nil];
    return YES;
}

// 编辑结束的唯一出口：回车、Esc、点输入框以外、面板收起都走到这里
- (void)controlTextDidEndEditing:(NSNotification *)n {
    if (!_editing) {
        return;
    }
    _editing = NO;
    NSString *name = [_name.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    BOOL changed = !_cancel && name.length && ![name isEqualToString:_saved];
    _name.stringValue = changed ? name : _saved;
    [self showAsLabel];
    if (changed && self.onRename) {
        self.onRename(name);
    }
}

@end

void endEditingOnOutsideClick(void) {
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown
                                          handler:^NSEvent *(NSEvent *e) {
                                              NSText *ed = (NSText *)e.window.firstResponder;
                                              if (![ed isKindOfClass:NSText.class] || !ed.isFieldEditor) {
                                                  return e;
                                              }
                                              NSView *field = (NSView *)ed.delegate;
                                              if ([field isKindOfClass:NSView.class] &&
                                                  !NSPointInRect([field convertPoint:e.locationInWindow fromView:nil],
                                                                 field.bounds)) {
                                                  [e.window makeFirstResponder:nil];
                                              }
                                              return e;
                                          }];
}
