# 远程模式的构建脚本。常用：make build、make app、make install、make dmg

APP_NAME    := 远程模式
EXECUTABLE  := remotemode
BUNDLE_ID   := local.remotemode
# 版本号只在 VERSION 文件里改
VERSION     := $(shell cat VERSION)
MIN_MACOS   := 12.0

BUILD       := build
DIST        := dist
BIN         := $(BUILD)/$(EXECUTABLE)
ICONSET     := $(BUILD)/AppIcon.iconset
ICNS        := $(BUILD)/AppIcon.icns
APP         := $(BUILD)/$(APP_NAME).app
DMG_STAGE   := $(BUILD)/dmg
DMG         := $(DIST)/$(APP_NAME).dmg
# 装在 /Applications：macOS 27 的菜单栏整理工具只认这里的应用，装在 ~/Applications 时菜单栏图标会被一直藏住
INSTALL_DIR := /Applications
OLD_INSTALL := $(HOME)/Applications/$(APP_NAME).app
INSTALLED   := $(INSTALL_DIR)/$(APP_NAME).app

SRCS    := $(wildcard src/*.m)
HDRS    := $(wildcard src/*.h)
CFLAGS  := -fobjc-arc -O2 -arch arm64 -arch x86_64 -mmacosx-version-min=$(MIN_MACOS) \
           -Wall -Wextra -Werror -Wno-unused-parameter
LDFLAGS := -framework Cocoa -framework CoreGraphics -framework ApplicationServices

.PHONY: build icon app dmg zip install selftest format clean

# 编出 arm64 和 x86_64 通用二进制
build: $(BIN)

$(BIN): $(SRCS) $(HDRS)
	@mkdir -p $(BUILD)
	clang $(CFLAGS) -o $@ $(SRCS) $(LDFLAGS)

# 用程序自己把图标画出来，再打成 icns
icon: $(ICNS)

$(ICNS): $(BIN)
	rm -rf $(ICONSET)
	$(BIN) --render-icon $(ICONSET)
	iconutil -c icns $(ICONSET) -o $@

# 组装 .app：可执行文件、图标、Info.plist，最后做 ad-hoc 签名
app: $(BIN) $(ICNS)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp $(BIN) "$(APP)/Contents/MacOS/$(EXECUTABLE)"
	cp $(ICNS) "$(APP)/Contents/Resources/AppIcon.icns"
	@# 界面文字的英文翻译：缺了就停，免得英文界面里冒出中文
	python3 tools/l10n.py
	cp -R Resources/*.lproj "$(APP)/Contents/Resources/"
	sed -e 's/@APP_NAME@/$(APP_NAME)/g' -e 's/@EXECUTABLE@/$(EXECUTABLE)/g' \
	    -e 's/@BUNDLE_ID@/$(BUNDLE_ID)/g' -e 's/@VERSION@/$(VERSION)/g' \
	    -e 's/@MIN_MACOS@/$(MIN_MACOS)/g' Resources/Info.plist.in > "$(APP)/Contents/Info.plist"
	@# 访达或同步盘会给文件夹加扩展属性，带着它们签不了名
	/usr/bin/xattr -cr "$(APP)"
	@# 没有开发者证书，只能临时签名。临时签名默认按程序内容认人，每次更新系统都当成新程序，辅助功能权限要重新勾。
	@# 这里把「认人」的条件写成只看包名，更新后权限保留
	codesign -s - --force --deep -r='designated => identifier "$(BUNDLE_ID)"' "$(APP)"

# 打包 dmg：应用、「应用程序」快捷方式、使用说明
dmg: app
	rm -rf $(DMG_STAGE)
	mkdir -p $(DMG_STAGE) $(DIST)
	cp -R "$(APP)" $(DMG_STAGE)/
	ln -s /Applications "$(DMG_STAGE)/应用程序"
	cp "Resources/使用说明.txt" $(DMG_STAGE)/
	rm -f "$(DMG)"
	hdiutil create -volname "$(APP_NAME)" -srcfolder $(DMG_STAGE) -ov -format UDZO "$(DMG)"

# 发布用的安装包：dist/PhoneMode-<版本>.zip，传到 GitHub Release，程序自动更新时下载它
zip: app
	@mkdir -p $(DIST)
	rm -f "$(DIST)/PhoneMode-$(VERSION).zip"
	/usr/bin/ditto -c -k --keepParent "$(APP)" "$(DIST)/PhoneMode-$(VERSION).zip"

# 装到 /Applications 并重新打开；正在运行的旧版本（包括以前装在 ~/Applications 的）先正常退出，让它把显示器恢复好
install: app
	-pkill -TERM -f "/Applications/$(APP_NAME).app/Contents/MacOS/$(EXECUTABLE)$$"
	@for i in 1 2 3 4 5 6 7 8 9 10 11 12; do \
	    pgrep -f "/Applications/$(APP_NAME).app/Contents/MacOS/$(EXECUTABLE)$$" >/dev/null || break; sleep 0.5; \
	done
	rm -rf "$(INSTALLED)" "$(OLD_INSTALL)"
	cp -R "$(APP)" "$(INSTALLED)"
	open "$(INSTALLED)"

# 自测：真实开一次虚拟屏，约 14 秒，期间显示器会切换几次
selftest: $(BIN)
	$(BIN) --selftest

format:
	xcrun clang-format -i src/*.m src/*.h

clean:
	rm -rf $(BUILD)
