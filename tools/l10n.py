#!/usr/bin/env python3
# 检查界面文字的英文翻译：源码里每个 L(@"…") 在 Resources/en.lproj/Localizable.strings 里都要有，多出来的也列出来。
# 用法：python3 tools/l10n.py（make app 时自动跑，缺翻译就停）
import re, sys, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
keys = []
for f in sorted(p for p in (root / 'src').glob('*.m') if p.name != 'SelfTest.m'):  # 自测只在开发时跑，不翻
    for m in re.finditer(r'L\(@"((?:[^"\\]|\\.)*)"\)', f.read_text()):
        if m.group(1) not in keys:
            keys.append(m.group(1))
    # 表里的 C 字符串（型号、分组），运行时用 NSLocalizedString 翻译：带中文的才要
    for line in f.read_text().split('\n'):
        code = line.split('//')[0]
        for m in re.finditer(r'(?<![@\w])"((?:[^"\\]|\\.)*[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef](?:[^"\\]|\\.)*)"', code):
            if 'L(@' not in code[max(0, m.start() - 4):m.start()] and m.group(1) not in keys:
                keys.append(m.group(1))
strings = root / 'Resources/en.lproj/Localizable.strings'
have = dict(re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', strings.read_text(), re.M)) if strings.exists() else {}
missing = [k for k in keys if k not in have]
extra = [k for k in have if k not in keys]
if '--list' in sys.argv:
    print('\n'.join(keys))
    sys.exit(0)
for k in missing:
    print(f'缺英文：{k}')
for k in extra:
    print(f'源码里没有了：{k}')
for k, v in have.items():
    if k.count('%@') != v.count('%@') or k.count('%d') != v.count('%d'):
        print(f'占位符对不上：{k} → {v}')
        missing.append(k)
sys.exit(1 if missing else 0)
