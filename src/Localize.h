// 界面文字：源码里写中文原文，系统语言是中文时原样显示，其他语言按 Resources/en.lproj/Localizable.strings 显示英文
#import <Foundation/Foundation.h>
#define L(s) NSLocalizedString(s, nil)

// 界面是不是中文（按系统语言挑出来的那一份）
static inline BOOL uiIsChinese(void) {
    return [NSBundle.mainBundle.preferredLocalizations.firstObject hasPrefix:@"zh"];
}
