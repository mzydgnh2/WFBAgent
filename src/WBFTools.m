//
//  WBFTools.m
//

#import "WBFTools.h"
#import "WBFTouch.h"
#import "WBFShell.h"
#import "WBFConfig.h"
#import <unistd.h>

NSString *const WBFToolFinishMarker = @"__WBF_FINISH__";

void (^WBFSnapshotOverlayHook)(BOOL hide) = NULL;

static void WBFSyncMain(dispatch_block_t block) {
    if (!block) return;
    if ([NSThread isMainThread]) block();
    else dispatch_sync(dispatch_get_main_queue(), block);
}

static double WBFNum(id v) {
    if ([v isKindOfClass:[NSNumber class]]) return [v doubleValue];
    if ([v isKindOfClass:[NSString class]]) return [v doubleValue];
    return 0;
}

static NSInteger WBFInt(id v) {
    return (NSInteger)llround(WBFNum(v));
}

static NSString *WBFStr(id v) {
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    if (v) return [v description];
    return @"";
}

static NSDictionary *WBFProp(NSString *type, NSString *desc, NSArray *enums) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"type"] = type;
    d[@"description"] = desc;
    if (enums.count) d[@"enum"] = enums;
    return d;
}

static NSDictionary *WBFTool(NSString *name, NSString *desc, NSDictionary *props, NSArray *required) {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"type"] = @"object";
    params[@"properties"] = props ?: @{};
    if (required.count) params[@"required"] = required;
    return @{@"type": @"function",
             @"function": @{@"name": name, @"description": desc, @"parameters": params}};
}

@implementation WBFTools

+ (instancetype)shared {
    static WBFTools *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        inst = [WBFTools new];
        inst.pendingImages = [NSMutableArray array];
        inst.elements = [NSMutableArray array];
    });
    return inst;
}

#pragma mark - schemas

- (NSArray *)schemas {
    return @[
        WBFTool(@"screenshot", @"截取当前 App 界面（不含悬浮面板）并作为图片交给模型分析。操作前建议先调用。", @{}, @[]),
        WBFTool(@"ui_tree", @"导出当前界面可交互元素的层级结构，每个元素带编号、文字、类名与坐标。用于精确定位后再 tap_element。",
                @{@"max_depth": WBFProp(@"integer", @"最大遍历深度，默认 18", nil)}, @[]),
        WBFTool(@"tap", @"在屏幕坐标(点)处执行一次真实点击。",
                @{@"x": WBFProp(@"number", @"横坐标(pt)", nil), @"y": WBFProp(@"number", @"纵坐标(pt)", nil)},
                @[@"x", @"y"]),
        WBFTool(@"tap_element", @"点击 ui_tree 输出中编号为 index 的元素中心点。",
                @{@"index": WBFProp(@"integer", @"元素编号", nil)}, @[@"index"]),
        WBFTool(@"swipe", @"从起点滑动到终点，可控制时长模拟快滑/慢滑。",
                @{@"x1": WBFProp(@"number", @"起点 x", nil), @"y1": WBFProp(@"number", @"起点 y", nil),
                  @"x2": WBFProp(@"number", @"终点 x", nil), @"y2": WBFProp(@"number", @"终点 y", nil),
                  @"duration": WBFProp(@"number", @"滑动时长秒，默认 0.35", nil)},
                @[@"x1", @"y1", @"x2", @"y2"]),
        WBFTool(@"long_press", @"在坐标处长按。",
                @{@"x": WBFProp(@"number", @"横坐标", nil), @"y": WBFProp(@"number", @"纵坐标", nil),
                  @"duration": WBFProp(@"number", @"按住秒数，默认 0.8", nil)},
                @[@"x", @"y"]),
        WBFTool(@"type_text", @"向当前聚焦的输入框输入文本（支持中文、emoji、多行）。输入前需先点击输入框。",
                @{@"text": WBFProp(@"string", @"要输入的文本", nil)}, @[@"text"]),
        WBFTool(@"press_key", @"发送按键：return 回车 / delete 退格 / space 空格。",
                @{@"key": WBFProp(@"string", @"按键名", @[@"return", @"delete", @"space"])}, @[@"key"]),
        WBFTool(@"shell", @"在设备上执行真实的 shell 命令并返回 stdout/stderr。可用于查看文件、进程、系统信息、修改配置等。",
                @{@"command": WBFProp(@"string", @"完整命令，如：ls -la /var/mobile", nil),
                  @"timeout": WBFProp(@"number", @"超时秒数，默认 20", nil)},
                @[@"command"]),
        WBFTool(@"app_info", @"获取当前 App 的 bundle id、版本、屏幕尺寸、系统版本、越狱环境与终端引擎信息。", @{}, @[]),
        WBFTool(@"list_apps", @"列出设备上已安装的 App（bundle id + 名称），用于 open_app。", @{}, @[]),
        WBFTool(@"open_app", @"通过 bundle id 启动另一个 App。",
                @{@"bundle_id": WBFProp(@"string", @"目标 App 的 bundle id", nil)}, @[@"bundle_id"]),
        WBFTool(@"open_url", @"用系统打开一个 URL 或 URL Scheme。",
                @{@"url": WBFProp(@"string", @"完整 URL", nil)}, @[@"url"]),
        WBFTool(@"read_file", @"读取设备上的文件（纯文本）。",
                @{@"path": WBFProp(@"string", @"绝对路径", nil),
                  @"max_bytes": WBFProp(@"integer", @"最多读取字节数，默认 20000", nil)},
                @[@"path"]),
        WBFTool(@"write_file", @"写入/覆盖设备上的文件。",
                @{@"path": WBFProp(@"string", @"绝对路径", nil),
                  @"content": WBFProp(@"string", @"文件内容", nil)},
                @[@"path", @"content"]),
        WBFTool(@"clipboard", @"读取或写入系统剪贴板。",
                @{@"action": WBFProp(@"string", @"get 或 set", @[@"get", @"set"]),
                  @"text": WBFProp(@"string", @"action=set 时的文本", nil)},
                @[@"action"]),
        WBFTool(@"http_request", @"发起一次 HTTP 请求并返回状态码与响应体，用于调用其他服务/API。",
                @{@"method": WBFProp(@"string", @"GET/POST/PUT/DELETE", nil),
                  @"url": WBFProp(@"string", @"URL", nil),
                  @"headers": WBFProp(@"object", @"请求头字典（可选）", nil),
                  @"body": WBFProp(@"string", @"请求体（可选）", nil)},
                @[@"url"]),
        WBFTool(@"wait", @"等待若干秒（页面加载、动画完成）。",
                @{@"seconds": WBFProp(@"number", @"秒数，最多 10", nil)}, @[@"seconds"]),
        WBFTool(@"finish", @"任务完成或无法继续时调用，给出最终结论给用户。",
                @{@"summary": WBFProp(@"string", @"给用户的最终答复，说明做了什么、结果如何", nil)},
                @[@"summary"])
    ];
}

#pragma mark - helpers

- (NSString *)appName {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *n = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: @"App";
    return n;
}

- (UIImage *)snapshot {
    __block UIImage *img = nil;
    WBFSyncMain(^{
        UIWindow *w = WBFHostWindow();
        if (!w) return;
        if (WBFSnapshotOverlayHook) WBFSnapshotOverlayHook(YES);
        CGSize size = w.bounds.size;
        if (size.width < 1 || size.height < 1) {
            if (WBFSnapshotOverlayHook) WBFSnapshotOverlayHook(NO);
            return;
        }
        CGFloat scale = [UIScreen mainScreen].scale;
        CGFloat maxDim = 1280.0;
        CGFloat longest = MAX(size.width, size.height) * scale;
        if (longest > maxDim) scale = maxDim / MAX(size.width, size.height);
        if (scale < 1.0) scale = 1.0;
        UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
        fmt.scale = scale;
        fmt.opaque = NO;
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt];
        img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            BOOL ok = [w drawViewHierarchyInRect:w.bounds afterScreenUpdates:YES];
            if (!ok) {
                CGContextRef c = ctx.CGContext;
                CGContextSaveGState(c);
                [w.layer renderInContext:c];
                CGContextRestoreGState(c);
            }
        }];
        if (WBFSnapshotOverlayHook) WBFSnapshotOverlayHook(NO);
    });
    return img;
}

static BOOL WBFViewUsable(UIView *v) {
    if (!v || v.hidden || v.alpha < 0.03) return NO;
    if (v.frame.size.width < 1.0 || v.frame.size.height < 1.0) return NO;
    return YES;
}

static NSString *WBFViewText(UIView *v) {
    if ([v isKindOfClass:[UILabel class]]) {
        NSString *t = ((UILabel *)v).text;
        if (t.length) return t;
    }
    if ([v isKindOfClass:[UIButton class]]) {
        UIButton *b = (UIButton *)v;
        NSString *t = [b titleForState:b.state];
        if (!t.length) t = b.currentTitle;
        if (!t.length) t = [b titleForState:UIControlStateNormal];
        if (t.length) return t;
    }
    if ([v isKindOfClass:[UITextField class]]) {
        UITextField *f = (UITextField *)v;
        if (f.text.length) return f.text;
        if (f.placeholder.length) return f.placeholder;
    }
    if ([v isKindOfClass:[UITextView class]]) {
        NSString *t = ((UITextView *)v).text;
        if (t.length) return t;
    }
    NSString *al = v.accessibilityLabel;
    if (al.length) return al;
    NSString *aid = v.accessibilityValue;
    if (aid.length) return aid;
    return nil;
}

- (void)walk:(UIView *)v depth:(NSInteger)d maxDepth:(NSInteger)md
        out:(NSMutableString *)out budget:(NSInteger *)budget window:(UIWindow *)w {
    if (*budget <= 0 || d > md) return;
    if (!WBFViewUsable(v)) return;
    (*budget)--;

    NSString *text = WBFViewText(v);
    BOOL control = [v isKindOfClass:[UIControl class]];
    BOOL cell = [v isKindOfClass:[UITableViewCell class]] || [v isKindOfClass:[UICollectionViewCell class]];
    BOOL hasId = v.accessibilityIdentifier.length > 0;
    BOOL inputable = [v isKindOfClass:[UITextField class]] || [v isKindOfClass:[UITextView class]] || [v isKindOfClass:[UISearchBar class]];

    if (text.length || control || cell || hasId) {
        CGRect r = [v convertRect:v.bounds toView:w];
        if (r.origin.x + r.size.width < 0 || r.origin.y + r.size.height < 0) {
            // still list, model can decide
        }
        NSInteger idx = (NSInteger)self.elements.count;
        [self.elements addObject:[NSValue valueWithNonretainedObject:v]];
        NSString *cls = NSStringFromClass(v.class);
        NSRange dot = [cls rangeOfString:@"." options:NSBackwardsSearch];
        if (dot.location != NSNotFound) cls = [cls substringFromIndex:dot.location + 1];
        if (cls.length > 34) cls = [cls substringToIndex:34];

        NSMutableString *line = [NSMutableString string];
        [line appendFormat:@"%@[%ld] %@", [@"" stringByPaddingToLength:(NSUInteger)MIN(d, 10) withString:@"  " startingAtIndex:0],
                          (long)idx, cls];
        if (text.length) {
            NSString *clean = [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            if (clean.length > 60) clean = [[clean substringToIndex:60] stringByAppendingString:@"…"];
            [line appendFormat:@" 「%@」", clean];
        }
        if (hasId) [line appendFormat:@" id=%@", v.accessibilityIdentifier];
        [line appendFormat:@" (%.0f,%.0f,%.0f,%.0f)", r.origin.x, r.origin.y, r.size.width, r.size.height];
        if (inputable) [line appendString:@" ⌨可输入"];
        else if (control || cell) [line appendString:@" ◉可点"];
        if (!v.userInteractionEnabled) [line appendString:@" ⊘不可交互"];
        [line appendString:@"\n"];
        [out appendString:line];
    }

    for (UIView *sub in v.subviews) {
        if (*budget <= 0) break;
        [self walk:sub depth:d + 1 maxDepth:md out:out budget:budget window:w];
    }
}

- (NSString *)dumpUITree:(NSInteger)maxDepth {
    __block NSString *result = nil;
    WBFSyncMain(^{
        UIWindow *w = WBFHostWindow();
        if (!w) { result = @"无法获取当前窗口"; return; }
        self.elements = [NSMutableArray array];
        NSMutableString *out = [NSMutableString string];
        CGRect sb = [UIScreen mainScreen].bounds;
        [out appendFormat:@"App: %@ (%@)\n屏幕: %.0fx%.0f pt, scale %.1f\n当前窗口: %@ %.0fx%.0f\n元素列表(格式: [编号] 类名 「文字」 id (x,y,w,h)):\n",
                       [self appName], [[NSBundle mainBundle] bundleIdentifier],
                       sb.size.width, sb.size.height, [UIScreen mainScreen].scale,
                       NSStringFromClass(w.class), w.bounds.size.width, w.bounds.size.height];
        NSInteger budget = 600;
        [self walk:w depth:0 maxDepth:(maxDepth > 0 ? maxDepth : 18) out:out budget:&budget window:w];
        if (!self.elements.count) [out appendString:@"(未发现可交互元素，可尝试 screenshot 查看)\n"];
        [out appendFormat:@"共 %lu 个可操作元素\n", (unsigned long)self.elements.count];
        result = out;
    });
    return result ?: @"无法导出界面";
}

#pragma mark - execution

- (NSString *)execute:(NSString *)name arguments:(NSDictionary *)args {
    if (![args isKindOfClass:[NSDictionary class]]) args = @{};
    NSString *n = WBFTrim(name);

    if ([n isEqualToString:@"screenshot"]) {
        UIImage *img = [self snapshot];
        if (!img) return @"截图失败：无法渲染当前窗口";
        NSData *jpeg = UIImageJPEGRepresentation(img, 0.62);
        if (!jpeg) return @"截图失败：编码错误";
        [self.pendingImages addObject:[jpeg base64EncodedStringWithOptions:0]];
        return [NSString stringWithFormat:@"已附带当前屏幕截图（%dx%d px），请据此判断界面。", (int)img.size.width, (int)img.size.height];
    }

    if ([n isEqualToString:@"ui_tree"]) {
        return [self dumpUITree:WBFInt(args[@"max_depth"])];
    }

    if ([n isEqualToString:@"tap"]) {
        CGFloat x = WBFNum(args[@"x"]), y = WBFNum(args[@"y"]);
        [WBFTouch tap:CGPointMake(x, y)];
        return [NSString stringWithFormat:@"已点击 (%.0f, %.0f) · 引擎:%@", x, y, [WBFTouch engineName]];
    }

    if ([n isEqualToString:@"tap_element"]) {
        NSInteger idx = WBFInt(args[@"index"]);
        if (idx < 0 || idx >= (NSInteger)self.elements.count) {
            return [NSString stringWithFormat:@"索引 %ld 越界（当前共 %lu 个元素），请先调用 ui_tree。",
                    (long)idx, (unsigned long)self.elements.count];
        }
        NSValue *val = self.elements[(NSUInteger)idx];
        UIView *v = [val nonretainedObjectValue];
        if (!v) return @"该元素已释放，请重新调用 ui_tree。";
        __block CGPoint pt = CGPointZero;
        __block NSString *label = @"";
        WBFSyncMain(^{
            CGPoint c = CGPointMake(CGRectGetMidX(v.bounds), CGRectGetMidY(v.bounds));
            CGPoint inWindow = [v convertPoint:c toView:v.window];
            UIWindow *win = v.window ?: WBFHostWindow();
            pt = CGPointMake(inWindow.x + win.frame.origin.x, inWindow.y + win.frame.origin.y);
            label = WBFViewText(v) ?: NSStringFromClass(v.class);
        });
        [WBFTouch tap:pt];
        return [NSString stringWithFormat:@"已点击 [%ld]「%@」@ (%.0f, %.0f)", (long)idx, label, pt.x, pt.y];
    }

    if ([n isEqualToString:@"swipe"]) {
        CGPoint a = CGPointMake(WBFNum(args[@"x1"]), WBFNum(args[@"y1"]));
        CGPoint b = CGPointMake(WBFNum(args[@"x2"]), WBFNum(args[@"y2"]));
        double d = WBFNum(args[@"duration"]);
        if (d <= 0.02) d = 0.35;
        [WBFTouch swipeFrom:a to:b duration:d];
        return [NSString stringWithFormat:@"已滑动 (%.0f,%.0f) → (%.0f,%.0f) 用时 %.2fs", a.x, a.y, b.x, b.y, d];
    }

    if ([n isEqualToString:@"long_press"]) {
        CGPoint p = CGPointMake(WBFNum(args[@"x"]), WBFNum(args[@"y"]));
        double d = WBFNum(args[@"duration"]);
        if (d <= 0.05) d = 0.8;
        [WBFTouch longPress:p duration:d];
        return [NSString stringWithFormat:@"已长按 (%.0f, %.0f) %.2fs", p.x, p.y, d];
    }

    if ([n isEqualToString:@"type_text"]) {
        NSString *t = WBFStr(args[@"text"]);
        BOOL ok = [WBFTouch typeText:t];
        return ok ? [NSString stringWithFormat:@"已输入 %lu 个字符", (unsigned long)t.length]
                  : @"输入失败：当前没有聚焦的输入框，请先点击输入框。";
    }

    if ([n isEqualToString:@"press_key"]) {
        NSString *k = WBFStr(args[@"key"]);
        if ([k isEqualToString:@"space"]) { [WBFTouch typeText:@" "]; return @"已输入空格"; }
        BOOL ok = [WBFTouch pressKey:k];
        return ok ? [NSString stringWithFormat:@"已发送按键 %@", k] : @"按键失败：无聚焦输入框";
    }

    if ([n isEqualToString:@"shell"]) {
        NSString *cmd = WBFStr(args[@"command"]);
        double to = WBFNum(args[@"timeout"]);
        if (to <= 0) to = 20;
        if (to > 60) to = 60;
        NSString *outStr = [[WBFShell shared] exec:cmd timeout:to];
        if (!outStr.length) outStr = @"(无输出)";
        if (outStr.length > 12000) outStr = [[outStr substringToIndex:12000] stringByAppendingString:@"\n…(输出已截断)"];
        return [NSString stringWithFormat:@"$ %@\n%@", cmd, outStr];
    }

    if ([n isEqualToString:@"app_info"]) {
        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        CGRect sb = [UIScreen mainScreen].bounds;
        UIDevice *dev = [UIDevice currentDevice];
        return [NSString stringWithFormat:
                @"App: %@\nbundle: %@\n版本: %@ (%@)\n设备: %@\niOS: %@\n屏幕: %.0fx%.0f @%.1fx\n安全区: top %.0f bottom %.0f\n触摸引擎: %@\n终端引擎: %@\n越狱: 已越狱 (roothide/rootless)",
                info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: @"?",
                [[NSBundle mainBundle] bundleIdentifier],
                info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?",
                dev.model, dev.systemVersion,
                sb.size.width, sb.size.height, [UIScreen mainScreen].scale,
                WBFHostWindow().safeAreaInsets.top, WBFHostWindow().safeAreaInsets.bottom,
                [WBFTouch engineName], [[WBFShell shared] engineName]];
    }

    if ([n isEqualToString:@"list_apps"]) {
        Class wsCls = NSClassFromString(@"LSApplicationWorkspace");
        if (!wsCls) return @"当前系统无法枚举应用（LSApplicationWorkspace 不可用）";
        id ws = ((id (*)(id, SEL))objc_msgSend)((id)wsCls, NSSelectorFromString(@"defaultWorkspace"));
        NSArray *all = ((id (*)(id, SEL))objc_msgSend)(ws, NSSelectorFromString(@"allInstalledApplications"));
        NSMutableString *out = [NSMutableString string];
        NSInteger cnt = 0;
        for (id proxy in all) {
            NSString *bid = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"applicationIdentifier"));
            if (!bid.length) bid = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"bundleIdentifier"));
            if (!bid.length) continue;
            NSString *nm = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"localizedName")) ?: @"";
            [out appendFormat:@"%@  |  %@\n", bid, nm];
            if (++cnt >= 250) break;
        }
        return cnt ? out : @"未获取到应用列表";
    }

    if ([n isEqualToString:@"open_app"]) {
        NSString *bid = WBFStr(args[@"bundle_id"]);
        Class wsCls = NSClassFromString(@"LSApplicationWorkspace");
        if (!wsCls) return @"LSApplicationWorkspace 不可用";
        id ws = ((id (*)(id, SEL))objc_msgSend)((id)wsCls, NSSelectorFromString(@"defaultWorkspace"));
        BOOL ok = ((BOOL (*)(id, SEL, id))objc_msgSend)(ws, NSSelectorFromString(@"openApplicationWithBundleID:"), bid);
        return ok ? [NSString stringWithFormat:@"已请求启动 %@", bid]
                  : [NSString stringWithFormat:@"启动 %@ 失败（bundle id 是否正确？）", bid];
    }

    if ([n isEqualToString:@"open_url"]) {
        NSString *u = WBFStr(args[@"url"]);
        NSURL *url = [NSURL URLWithString:u];
        if (!url) return @"URL 无效";
        __block BOOL ok = NO;
        WBFSyncMain(^{
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) { ok = success; }];
        });
        return [NSString stringWithFormat:@"已打开 %@", u];
    }

    if ([n isEqualToString:@"read_file"]) {
        NSString *p = WBFStr(args[@"path"]);
        NSInteger maxB = WBFInt(args[@"max_bytes"]);
        if (maxB <= 0) maxB = 20000;
        NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:p];
        if (!fh) return [NSString stringWithFormat:@"无法打开 %@（不存在或无权限）", p];
        NSData *d = [fh readDataOfLength:(NSUInteger)maxB];
        [fh closeFile];
        NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        if (!s) return [NSString stringWithFormat:@"%@ 为二进制文件，共 %lu 字节（前 8 字节: %@）", p, (unsigned long)d.length,
                        [d subdataWithRange:NSMakeRange(0, MIN((NSUInteger)8, d.length))]];
        return s.length ? s : @"(空文件)";
    }

    if ([n isEqualToString:@"write_file"]) {
        NSString *p = WBFStr(args[@"path"]);
        NSString *c = WBFStr(args[@"content"]);
        NSString *dir = [p stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        BOOL ok = [[c dataUsingEncoding:NSUTF8StringEncoding] writeToFile:p atomically:YES];
        return ok ? [NSString stringWithFormat:@"已写入 %lu 字节 → %@", (unsigned long)c.length, p]
                  : [NSString stringWithFormat:@"写入失败（权限不足？）：%@", p];
    }

    if ([n isEqualToString:@"clipboard"]) {
        NSString *act = WBFStr(args[@"action"]);
        if ([act isEqualToString:@"set"]) {
            NSString *t = WBFStr(args[@"text"]);
            [UIPasteboard generalPasteboard].string = t;
            return [NSString stringWithFormat:@"剪贴板已设为 %lu 字符", (unsigned long)t.length];
        }
        return [NSString stringWithFormat:@"剪贴板内容：%@", [UIPasteboard generalPasteboard].string ?: @"(空)"];
    }

    if ([n isEqualToString:@"http_request"]) {
        NSString *urlStr = WBFStr(args[@"url"]);
        NSURL *url = [NSURL URLWithString:urlStr];
        if (!url) return @"URL 无效";
        NSString *method = WBFStr(args[@"method"]);
        if (!method.length) method = @"GET";
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.HTTPMethod = method.uppercaseString;
        req.timeoutInterval = 25;
        NSDictionary *headers = args[@"headers"];
        if ([headers isKindOfClass:[NSDictionary class]]) {
            for (NSString *k in headers) [req setValue:WBFStr(headers[k]) forHTTPHeaderField:k];
        }
        NSString *body = WBFStr(args[@"body"]);
        if (body.length) req.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block NSString *result = @"请求超时";
        [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            NSMutableString *s = [NSMutableString string];
            if (err) [s appendFormat:@"错误: %@", err.localizedDescription];
            else {
                NSInteger status = 0;
                if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
                    NSHTTPURLResponse *h = (NSHTTPURLResponse *)resp;
                    status = h.statusCode;
                    [s appendFormat:@"HTTP %ld\n", (long)status];
                }
                NSString *txt = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
                if (!txt) txt = data ? [NSString stringWithFormat:@"<二进制 %lu 字节>", (unsigned long)data.length] : @"";
                if (txt.length > 4000) txt = [[txt substringToIndex:4000] stringByAppendingString:@"\n…(截断)"];
                [s appendString:txt];
            }
            result = s;
            dispatch_semaphore_signal(sem);
        }] resume];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(28 * NSEC_PER_SEC)));
        return result;
    }

    if ([n isEqualToString:@"wait"]) {
        double s = WBFNum(args[@"seconds"]);
        if (s <= 0) s = 1;
        if (s > 10) s = 10;
        usleep((useconds_t)(s * 1e6));
        return [NSString stringWithFormat:@"已等待 %.1fs", s];
    }

    if ([n isEqualToString:@"finish"]) {
        return [WBFToolFinishMarker stringByAppendingString:WBFStr(args[@"summary"])];
    }

    return [NSString stringWithFormat:@"未知工具: %@", n];
}

@end
