//
//  WBFAgent.m
//

#import "WBFAgent.h"
#import "WBFLLM.h"
#import "WBFTools.h"
#import "WBFTouch.h"
#import "WBFShell.h"

@interface WBFAgent ()
@property (nonatomic, assign) BOOL running;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSString *currentTask;
@property (nonatomic, assign) NSInteger sessionTokens;
@end

@implementation WBFAgent

+ (instancetype)shared {
    static WBFAgent *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        inst = [WBFAgent new];
        inst.messages = [NSMutableArray array];
        inst.queue = dispatch_queue_create("com.wbf.agent", DISPATCH_QUEUE_SERIAL);
    });
    return inst;
}

- (void)emit:(NSString *)type info:(NSDictionary *)info {
    WBFDispatchMain(^{
        if (self.onEvent) self.onEvent(type, info ?: @{});
    });
}

- (NSInteger)contextPercent {
    WBFConfig *cfg = [WBFConfig shared];
    if (cfg.maxContext <= 0) return 0;
    NSInteger est = WBFEstimateMessages(self.messages);
    NSInteger used = MAX(est, self.usedTokens);
    NSInteger p = (NSInteger)round((double)used / (double)cfg.maxContext * 100.0);
    return MIN(100, MAX(0, p));
}

#pragma mark - system prompt

- (NSString *)systemPrompt {
    CGRect sb = [UIScreen mainScreen].bounds;
    UIEdgeInsets ins = WBFHostWindow().safeAreaInsets;
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *appName = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: @"App";
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"?";

    return [NSString stringWithFormat:
            @"你是 WBF Agent，一个直接运行在 iOS App 进程内的全权限智能体。你不是聊天机器人，而是「手」——你通过真实工具去操作设备。\n"
            @"\n"
            @"## 当前环境\n"
            @"- App: %@ (%@)\n"
            @"- 屏幕: %.0f x %.0f pt（坐标原点在左上角，单位是 pt，不是像素）\n"
            @"- 安全区: 顶部 %.0f pt，底部 %.0f pt\n"
            @"- 系统: iOS %@\n"
            @"\n"
            @"## 你的能力（全部为真实实现，非模拟）\n"
            @"- screenshot：截取当前界面给视觉模型看\n"
            @"- ui_tree：导出元素树，返回带编号的元素（点击优先用 tap_element，更准）\n"
            @"- tap / tap_element / swipe / long_press：真实 HID 触摸注入\n"
            @"- type_text / press_key：向聚焦输入框真实输入\n"
            @"- shell：设备上真实 shell（可读写文件、查进程、改配置）\n"
            @"- read_file / write_file / clipboard / http_request / open_app / open_url / list_apps / app_info / wait\n"
            @"\n"
            @"## 工作准则\n"
            @"1. 先观察再行动：每次重要操作前后用 screenshot 或 ui_tree 确认界面状态，不要凭想象点击。\n"
            @"2. 点击优先用 tap_element（基于 ui_tree 编号），坐标法仅作兜底。\n"
            @"3. 输入文字前必须先 tap 输入框让它获得焦点；输入后可用 screenshot 校验。\n"
            @"4. 一次只做一小步，观察结果后再决定下一步；不要连续盲点。\n"
            @"5. 同一操作失败两次就换思路（换元素、滚动、返回、用 shell 查状态）。\n"
            @"6. 遇到弹窗、广告、权限请求、登录过期：先按最合理方式处理掉，再继续原任务。\n"
            @"7. 页面跳转/加载后先 wait 0.5~1.5 秒再截图，避免抓到中间态。\n"
            @"8. 不要向用户提问、不要要求确认——你没有对话通道，只能靠工具推进任务。\n"
            @"9. 任务完成或确认无法完成时，必须调用 finish 给出最终结论（中文，说明做了什么、结果如何）。\n"
            @"\n"
            @"## 输出风格\n"
            @"执行过程中用一句话说明你正在做什么（中文），然后调用工具。不要输出冗余解释。",
            appName, bid, sb.size.width, sb.size.height, ins.top, ins.bottom,
            [[UIDevice currentDevice] systemVersion]];
}

#pragma mark - task lifecycle

- (void)resetContext {
    [self.messages removeAllObjects];
    self.usedTokens = 0;
    self.sessionTokens = 0;
    self.step = 0;
    [[WBFTools shared].elements removeAllObjects];
    [[WBFTools shared].pendingImages removeAllObjects];
}

- (void)startTask:(NSString *)task {
    if (self.running) {
        [self emit:@"error" info:@{@"text": @"当前仍有任务在执行，请先停止。"}];
        return;
    }
    NSString *t = WBFTrim(task);
    if (!t.length) {
        [self emit:@"error" info:@{@"text": @"任务内容为空。"}];
        return;
    }
    WBFConfig *cfg = [WBFConfig shared];
    if (!WBFTrim(cfg.apiKey).length) {
        [self emit:@"error" info:@{@"text": @"请先在「设置」里填写 API Key。"}];
        return;
    }

    self.running = YES;
    self.step = 0;
    self.currentTask = t;
    if (!self.messages.count) {
        [self.messages addObject:[WBFMsg role:@"system" content:[self systemPrompt]]];
    }
    // 每个新任务清掉上一轮的截图，避免干扰
    [[WBFTools shared].pendingImages removeAllObjects];

    WBFMsg *u = [WBFMsg role:@"user" content:t];
    if (cfg.inputMode == 1) {
        UIImage *img = [[WBFTools shared] snapshot];
        NSData *j = img ? UIImageJPEGRepresentation(img, 0.6) : nil;
        if (j) u.images = @[[j base64EncodedStringWithOptions:0]];
    } else if (cfg.inputMode == 2) {
        NSString *tree = [[WBFTools shared] dumpUITree:18];
        u.content = [NSString stringWithFormat:@"%@\n\n【当前界面结构】\n%@", t, tree];
    }
    [self.messages addObject:u];

    self.record = [WBFTaskRecord newTask:t];
    self.record.status = @"running";
    [[WBFConfig shared] addRecord:self.record];

    [self emit:@"user" info:@{@"text": t}];
    [self emit:@"tokens" info:@{@"used": @([self currentUsed]), @"limit": @(cfg.maxContext), @"step": @0}];

    __weak typeof(self) weakSelf = self;
    dispatch_async(self.queue, ^{
        [weakSelf runStep];
    });
}

- (NSInteger)currentUsed {
    NSInteger est = WBFEstimateMessages(self.messages);
    return MAX(est, self.usedTokens);
}

- (void)finishWith:(NSString *)summary status:(NSString *)status {
    self.running = NO;
    if (self.record) {
        self.record.status = status ?: @"done";
        self.record.tokens = [self currentUsed];
        self.record.steps = self.step;
        [[WBFConfig shared] saveHistory];
    }
    [self emit:@"done" info:@{@"text": summary ?: @"任务结束", @"status": status ?: @"done"}];
}

- (void)stop {
    if (!self.running) return;
    self.running = NO;
    if (self.record) {
        self.record.status = @"stopped";
        self.record.tokens = [self currentUsed];
        self.record.steps = self.step;
        [[WBFConfig shared] saveHistory];
    }
    [self emit:@"done" info:@{@"text": @"已手动停止。", @"status": @"stopped"}];
}

#pragma mark - context management

- (void)trimContext {
    WBFConfig *cfg = [WBFConfig shared];
    NSInteger limit = cfg.maxContext > 0 ? cfg.maxContext : 128000;
    NSInteger budget = (NSInteger)((double)limit * 0.78);
    if (WBFEstimateMessages(self.messages) <= budget) return;

    BOOL trimmed = NO;
    while (WBFEstimateMessages(self.messages) > budget && self.messages.count > 3) {
        // 保留 system，丢弃最早的 user/assistant/tool
        NSUInteger idx = 1;
        if (idx < self.messages.count) {
            [self.messages removeObjectAtIndex:idx];
            trimmed = YES;
        }
    }
    if (trimmed) {
        self.usedTokens = WBFEstimateMessages(self.messages);
        [self emit:@"truncated" info:@{@"text": @"上下文接近上限，已自动丢弃较早的对话记录。"}];
    }
}

#pragma mark - main loop

- (void)runStep {
    if (!self.running) return;
    WBFConfig *cfg = [WBFConfig shared];
    if (self.step >= cfg.maxSteps) {
        [self finishWith:[NSString stringWithFormat:@"已达到最大步数 %ld，任务暂停。可继续发送指令接续。", (long)cfg.maxSteps]
                  status:@"stopped"];
        return;
    }

    [self trimContext];
    [self emit:@"thinking" info:@{@"on": @YES}];
    [self emit:@"tokens" info:@{@"used": @([self currentUsed]), @"limit": @(cfg.maxContext), @"step": @(self.step)}];

    NSArray *tools = [[WBFTools shared] schemas];
    __weak typeof(self) weakSelf = self;
    [[WBFLLM shared] chat:self.messages tools:tools completion:^(NSDictionary *message, NSDictionary *usage, NSError *error) {
        WBFAgent *self_ = weakSelf;
        if (!self_) return;
        dispatch_async(self_.queue, ^{
            [self_ handleResponse:message usage:usage error:error];
        });
    }];
}

- (void)handleResponse:(NSDictionary *)message usage:(NSDictionary *)usage error:(NSError *)error {
    if (!self.running) return;
    [self emit:@"thinking" info:@{@"on": @NO}];

    if (error) {
        [self emit:@"error" info:@{@"text": error.localizedDescription ?: @"请求失败"}];
        [self finishWith:[NSString stringWithFormat:@"请求失败：%@", error.localizedDescription] status:@"failed"];
        return;
    }

    WBFConfig *cfg = [WBFConfig shared];
    NSInteger total = [usage[@"total_tokens"] integerValue];
    if (total > 0) {
        self.usedTokens = total;
    } else {
        self.usedTokens = WBFEstimateMessages(self.messages);
    }
    [self emit:@"tokens" info:@{@"used": @([self currentUsed]), @"limit": @(cfg.maxContext), @"step": @(self.step)}];

    id contentObj = message[@"content"];
    NSString *content = nil;
    if ([contentObj isKindOfClass:[NSString class]]) content = contentObj;
    else if ([contentObj isKindOfClass:[NSArray class]]) {
        NSMutableString *s = [NSMutableString string];
        for (id part in (NSArray *)contentObj) {
            if ([part isKindOfClass:[NSDictionary class]] && [part[@"text"] isKindOfClass:[NSString class]]) {
                [s appendString:part[@"text"]];
            }
        }
        content = s;
    }

    NSArray *rawCalls = message[@"tool_calls"];
    NSMutableArray *calls = [NSMutableArray array];
    if ([rawCalls isKindOfClass:[NSArray class]]) {
        for (NSDictionary *c in (NSArray *)rawCalls) {
            if (![c isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *fn = c[@"function"];
            if (![fn isKindOfClass:[NSDictionary class]]) continue;
            NSString *cid = c[@"id"] ?: [[NSUUID UUID] UUIDString];
            NSString *fname = fn[@"name"] ?: @"";
            id argsRaw = fn[@"arguments"];
            NSString *argsStr = @"{}";
            if ([argsRaw isKindOfClass:[NSString class]]) argsStr = argsRaw;
            else if ([argsRaw isKindOfClass:[NSDictionary class]]) {
                NSData *d = [NSJSONSerialization dataWithJSONObject:argsRaw options:0 error:NULL];
                if (d) argsStr = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"{}";
            }
            [calls addObject:@{@"id": cid, @"name": fname, @"args": argsStr}];
        }
    }

    WBFMsg *assistant = [WBFMsg role:@"assistant" content:content ?: @""];
    assistant.toolCalls = calls;
    [self.messages addObject:assistant];

    if (content.length) {
        [self emit:@"assistant" info:@{@"text": content}];
        if (self.record) [self.record.log addObject:@{@"role": @"assistant", @"text": content}];
    }

    if (!calls.count) {
        NSString *finalText = content.length ? content : @"模型未返回内容。";
        [self finishWith:finalText status:@"done"];
        return;
    }

    self.step++;
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.queue, ^{
        WBFAgent *strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf executeCalls:calls];
    });
}

- (void)executeCalls:(NSArray *)calls {
    BOOL finished = NO;
    NSString *finishSummary = nil;
    BOOL sawScreenshot = NO;

    for (NSDictionary *call in calls) {
        if (!self.running) return;
        NSString *name = call[@"name"];
        NSString *argsStr = call[@"args"];
        NSString *cid = call[@"id"];

        NSDictionary *args = @{};
        NSData *d = [argsStr dataUsingEncoding:NSUTF8StringEncoding];
        if (d) {
            id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
            if ([obj isKindOfClass:[NSDictionary class]]) args = obj;
        }

        [self emit:@"tool" info:@{@"name": name ?: @"?", @"args": args, @"state": @"running"}];

        NSMutableArray *imgs = [[WBFTools shared] pendingImages];
        [imgs removeAllObjects];

        NSString *result = [[WBFTools shared] execute:name arguments:args];
        if (!result) result = @"(无返回)";
        if (result.length > 8000) result = [[result substringToIndex:8000] stringByAppendingString:@"\n…(已截断)"];

        [self emit:@"tool" info:@{@"name": name ?: @"?", @"args": args, @"state": @"done",
                                  @"result": result}];
        if (self.record) {
            [self.record.log addObject:@{@"role": @"tool", @"text": result, @"name": name ?: @""}];
        }

        if ([result hasPrefix:WBFToolFinishMarker]) {
            finished = YES;
            finishSummary = [result substringFromIndex:WBFToolFinishMarker.length];
        }

        WBFMsg *toolMsg = [WBFMsg role:@"tool" content:result];
        toolMsg.toolCallId = cid;
        [self.messages addObject:toolMsg];

        if ([name isEqualToString:@"screenshot"]) sawScreenshot = YES;

        if (imgs.count) {
            WBFMsg *imgMsg = [WBFMsg role:@"user" content:@"【当前屏幕截图】"];
            imgMsg.images = [NSArray arrayWithArray:imgs];
            [self.messages addObject:imgMsg];
            [imgs removeAllObjects];
            sawScreenshot = YES;
        }

        if ([name isEqualToString:@"wait"] || [name isEqualToString:@"tap"] ||
            [name isEqualToString:@"tap_element"] || [name isEqualToString:@"swipe"] ||
            [name isEqualToString:@"long_press"]) {
            // 给系统一点时间渲染，再进入下一步
            usleep((useconds_t)(0.45 * 1e6));
        }
    }

    if (finished) {
        [self finishWith:finishSummary status:@"done"];
        return;
    }
    if (!self.running) return;

    WBFConfig *cfgNow = [WBFConfig shared];
    if (cfgNow.sendScreenshot && !sawScreenshot) {
        UIImage *img = [[WBFTools shared] snapshot];
        NSData *j = img ? UIImageJPEGRepresentation(img, 0.58) : nil;
        if (j) {
            WBFMsg *imgMsg = [WBFMsg role:@"user" content:@"【操作后的当前屏幕截图】"];
            imgMsg.images = @[[j base64EncodedStringWithOptions:0]];
            [self.messages addObject:imgMsg];
        }
    }

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), self.queue, ^{
        [weakSelf runStep];
    });
}

@end
