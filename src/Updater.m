#import "Updater.h"

#define CHECK_EVERY (24 * 3600)
#define SKIP_KEY @"updateSkipVersion" // 用户点了「跳过这个版本」的版本号

@implementation Updater {
    NSString *_repo;
    NSString *_pendingApp;  // 下载解压好、等着装的新程序包
    BOOL _busy;             // 正在检查或下载，不重复开始
    NSMutableArray *_open;  // 正在显示的提示框，显示期间要留着
    NSMutableDictionary *_handlers; // 提示框窗口 -> 点了第几个按钮之后做什么
}

+ (instancetype)shared {
    static Updater *u;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        u = [Updater new];
    });
    return u;
}

static NSString *currentVersion(void) {
    return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";
}

static NSString *appName(void) {
    return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"] ?: @"本程序";
}

// 按点分的数字逐段比，1.10 比 1.9 新。tag 前面的 v 去掉
static NSComparisonResult compareVersions(NSString *a, NSString *b) {
    NSArray *x = [[a stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"vV"]] componentsSeparatedByString:@"."];
    NSArray *y = [[b stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"vV"]] componentsSeparatedByString:@"."];
    for (NSUInteger i = 0; i < MAX(x.count, y.count); i++) {
        NSInteger p = i < x.count ? [x[i] integerValue] : 0, q = i < y.count ? [y[i] integerValue] : 0;
        if (p != q) {
            return p < q ? NSOrderedAscending : NSOrderedDescending;
        }
    }
    return NSOrderedSame;
}

// 提示框不用 runModal：菜单栏程序常常没法被系统切到前台，模态框弹出来却看不见，程序又卡在那里等，
// 别的事全停了。改成浮在最上层、不卡程序的窗口，点按钮后回调 done（参数是第几个按钮，从 0 开始）
- (void)show:(NSString *)title text:(NSString *)text buttons:(NSArray<NSString *> *)buttons done:(void (^)(NSInteger))done {
    if (!_open) {
        _open = [NSMutableArray array];
        _handlers = [NSMutableDictionary dictionary];
    }
    NSAlert *a = [NSAlert new];
    a.messageText = title;
    a.informativeText = text ?: @"";
    for (NSString *b in buttons.count ? buttons : @[ @"好" ]) {
        [a addButtonWithTitle:b];
    }
    for (NSUInteger i = 0; i < a.buttons.count; i++) {
        a.buttons[i].tag = (NSInteger)i;
        a.buttons[i].target = self;
        a.buttons[i].action = @selector(pressed:);
    }
    [a layout];
    NSWindow *w = a.window;
    w.level = NSFloatingWindowLevel;
    w.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    [w center];
    [_open addObject:a];
    _handlers[@((NSUInteger)w)] = done ? (id)[done copy] : (id) ^ (NSInteger i){};
    [NSApp activateIgnoringOtherApps:YES];
    [w makeKeyAndOrderFront:nil];
    [w orderFrontRegardless];
}

- (void)pressed:(NSButton *)b {
    NSWindow *w = b.window;
    void (^done)(NSInteger) = _handlers[@((NSUInteger)w)];
    [_handlers removeObjectForKey:@((NSUInteger)w)];
    [w orderOut:nil];
    for (NSAlert *a in [_open copy]) {
        if (a.window == w) {
            [_open removeObject:a];
        }
    }
    if (done) {
        done(b.tag);
    }
}

static void alert(NSString *title, NSString *text) {
    [[Updater shared] show:title text:text buttons:@[] done:nil];
}

- (void)startWithRepo:(NSString *)repo {
    _repo = repo;
    if (![NSBundle.mainBundle.bundlePath hasSuffix:@".app"]) {
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self check:NO];
    });
    NSTimer *t = [NSTimer timerWithTimeInterval:CHECK_EVERY
                                        repeats:YES
                                          block:^(NSTimer *x) {
                                              [self check:NO];
                                          }];
    [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
}

- (void)checkNow {
    [self check:YES];
}

// 读最新的 Release。manual 表示用户手动点的：没新版、出错都要告诉他，也不管「跳过这个版本」
- (void)check:(BOOL)manual {
    if (_busy || !_repo) {
        return;
    }
    if (_pendingApp) {
        if (manual) {
            alert(@"新版本已经下载好", @"等远程画面关闭后会自动安装。");
        }
        return;
    }
    _busy = YES;
    NSString *url = [NSString stringWithFormat:@"https://api.github.com/repos/%@/releases/latest", _repo];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:appName() forHTTPHeaderField:@"User-Agent"];
    req.timeoutInterval = 20;
    [[NSURLSession.sharedSession dataTaskWithRequest:req
                                   completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
                                       NSDictionary *rel = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
                                       dispatch_async(dispatch_get_main_queue(), ^{
                                           self->_busy = NO;
                                           [self handleRelease:[rel isKindOfClass:NSDictionary.class] ? rel : nil manual:manual];
                                       });
                                   }] resume];
}

- (void)handleRelease:(NSDictionary *)rel manual:(BOOL)manual {
    NSString *tag = [rel[@"tag_name"] isKindOfClass:NSString.class] ? rel[@"tag_name"] : nil;
    if (!tag) {
        if (manual) {
            alert(@"检查更新失败", @"连不上 GitHub，稍后再试。");
        }
        return;
    }
    NSString *ver = [tag stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"vV"]];
    if (compareVersions(ver, currentVersion()) != NSOrderedDescending) {
        if (manual) {
            alert(@"已经是最新版本", [NSString stringWithFormat:@"%@ %@", appName(), currentVersion()]);
        }
        return;
    }
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    if (!manual && [[ud stringForKey:SKIP_KEY] isEqualToString:ver]) {
        return;
    }
    NSString *zip = nil;
    for (NSDictionary *a in [rel[@"assets"] isKindOfClass:NSArray.class] ? rel[@"assets"] : @[]) {
        if ([a isKindOfClass:NSDictionary.class] && [a[@"name"] hasSuffix:@".zip"]) {
            zip = a[@"browser_download_url"];
            break;
        }
    }
    if (!zip) {
        if (manual) {
            alert(@"新版本还没有安装包", @"稍后再试。");
        }
        return;
    }
    // 更新说明太长就截断，提示框放不下
    NSString *notes = [rel[@"body"] isKindOfClass:NSString.class] ? rel[@"body"] : @"";
    if (notes.length > 600) {
        notes = [[notes substringToIndex:600] stringByAppendingString:@"…"];
    }
    _busy = YES; // 提示框开着时不再重复检查、重复弹
    [self show:[NSString stringWithFormat:@"%@ 有新版本 %@", appName(), ver]
          text:[NSString stringWithFormat:@"当前是 %@。\n\n%@", currentVersion(), notes]
       buttons:@[ @"更新", @"稍后", @"跳过这个版本" ]
          done:^(NSInteger i) {
              self->_busy = NO;
              if (i == 2) {
                  [ud setObject:ver forKey:SKIP_KEY];
              } else if (i == 0) {
                  [self download:zip];
              }
          }];
}

// 下载、解压，核对解出来的程序和本程序是同一个（包标识相同），再装
- (void)download:(NSString *)url {
    _busy = YES;
    [[NSURLSession.sharedSession
        downloadTaskWithURL:[NSURL URLWithString:url]
          completionHandler:^(NSURL *file, NSURLResponse *resp, NSError *err) {
              NSString *app = nil;
              if (file && !err) {
                  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
                  [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
                  NSString *zipPath = [dir stringByAppendingPathComponent:@"update.zip"];
                  [[NSFileManager defaultManager] moveItemAtPath:file.path toPath:zipPath error:nil];
                  NSTask *t = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/ditto" arguments:@[ @"-x", @"-k", zipPath, dir ]];
                  [t waitUntilExit];
                  for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) {
                      NSString *p = [dir stringByAppendingPathComponent:f];
                      NSBundle *b = [f hasSuffix:@".app"] ? [NSBundle bundleWithPath:p] : nil;
                      if ([b.bundleIdentifier isEqualToString:NSBundle.mainBundle.bundleIdentifier]) {
                          app = p;
                      }
                  }
              }
              dispatch_async(dispatch_get_main_queue(), ^{
                  self->_busy = NO;
                  if (!app) {
                      alert(@"更新失败", @"安装包下载或解压没成功，稍后再试。");
                      return;
                  }
                  self->_pendingApp = app;
                  if (self.canInstallNow && !self.canInstallNow()) {
                      alert(@"新版本已经下载好", @"远程画面正开着，关闭后会自动安装。");
                      return;
                  }
                  [self installPendingIfReady];
              });
          }] resume];
}

// 退出本程序，等它退干净后用一段脚本换程序包：旧的先挪开，新的拷进去，失败就换回旧的；最后重新打开
- (void)installPendingIfReady {
    if (!_pendingApp || (self.canInstallNow && !self.canInstallNow())) {
        return;
    }
    NSString *dest = NSBundle.mainBundle.bundlePath;
    NSString *script = [NSString stringWithFormat:
                                     @"while kill -0 %d 2>/dev/null; do sleep 0.2; done\n"
                                     @"rm -rf \"$DEST.old\"\n"
                                     @"if mv \"$DEST\" \"$DEST.old\" && /usr/bin/ditto \"$NEW\" \"$DEST\"; then rm -rf \"$DEST.old\"; "
                                     @"else rm -rf \"$DEST\"; mv \"$DEST.old\" \"$DEST\"; fi\n"
                                     @"/usr/bin/xattr -cr \"$DEST\"\n"
                                     @"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f \"$DEST\"\n"
                                     @"open \"$DEST\"\n",
                                     NSProcessInfo.processInfo.processIdentifier];
    NSTask *t = [NSTask new];
    t.launchPath = @"/bin/sh";
    t.arguments = @[ @"-c", [NSString stringWithFormat:@"nohup /bin/sh -c '%@' >/dev/null 2>&1 &",
                                                       [script stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]] ];
    t.environment = @{@"DEST" : dest, @"NEW" : _pendingApp, @"PATH" : @"/usr/bin:/bin:/usr/sbin:/sbin"};
    [t launch];
    [t waitUntilExit];
    _pendingApp = nil;
    [NSApp terminate:nil];
}

@end
