//
//  WBFViews.m
//  Task / Terminal / Tools / Settings tabs
//

#import "WBFInternal.h"
#import "WBFAgent.h"
#import "WBFTools.h"
#import "WBFTouch.h"
#import "WBFShell.h"
#import "WBFLLM.h"
#import <unistd.h>

static NSString *WBFShortNumber(NSInteger v) {
    if (v >= 1000000) return [NSString stringWithFormat:@"%.1fM", v / 1000000.0];
    if (v >= 1000) return [NSString stringWithFormat:@"%.1fk", v / 1000.0];
    return [NSString stringWithFormat:@"%ld", (long)v];
}

static UIColor *WBFHexText(void) {
    return [UIColor colorWithRed:0.80 green:0.86 blue:0.94 alpha:1.0];
}

#pragma mark - Task view

@interface WBFTaskView () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIView *stack;
@property (nonatomic, strong) NSMutableArray<WBFBubble *> *bubbles;
@property (nonatomic, strong) UIButton *sendBtn;
@property (nonatomic, strong) UITextField *input;
@property (nonatomic, strong) UILabel *ctxLabel;
@property (nonatomic, strong) UILabel *emptyHint;
@property (nonatomic, strong) UIView *progressBg;
@property (nonatomic, strong) UIView *progressFill;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, weak) WBFBubble *thinkingBubble;
@end

@implementation WBFTaskView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [WBFTheme bg0];
    self.bubbles = [NSMutableArray array];

    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scroll.backgroundColor = [UIColor clearColor];
    _scroll.alwaysBounceVertical = YES;
    _scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self addSubview:_scroll];

    _stack = [[UIView alloc] initWithFrame:CGRectZero];
    _stack.backgroundColor = [UIColor clearColor];
    [_scroll addSubview:_stack];

    _emptyHint = [[UILabel alloc] initWithFrame:CGRectZero];
    _emptyHint.numberOfLines = 0;
    _emptyHint.textAlignment = NSTextAlignmentCenter;
    _emptyHint.textColor = [WBFTheme sub];
    _emptyHint.font = [WBFTheme font:12 weight:UIFontWeightRegular];
    _emptyHint.text = @"输入任务，AI 会在当前 App 内真实操作\n例：帮我把这条笔记改成「明天开会」\n例：滚动到底部，截图看看有什么\n例：在搜索框里搜「火锅」并打开第一条";
    [self addSubview:_emptyHint];

    _progressBg = [[UIView alloc] initWithFrame:CGRectZero];
    _progressBg.backgroundColor = [WBFTheme bg2];
    _progressBg.layer.cornerRadius = 1;
    [self addSubview:_progressBg];

    _progressFill = [[UIView alloc] initWithFrame:CGRectZero];
    _progressFill.backgroundColor = [WBFTheme accent];
    _progressFill.layer.cornerRadius = 1;
    [_progressBg addSubview:_progressFill];

    _ctxLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _ctxLabel.font = [WBFTheme font:9.5 weight:UIFontWeightRegular];
    _ctxLabel.textColor = [WBFTheme sub];
    _ctxLabel.text = @"上下文 -- / --";
    [self addSubview:_ctxLabel];

    _inputBar = [[UIView alloc] initWithFrame:CGRectZero];
    _inputBar.backgroundColor = [WBFTheme bg1];
    _inputBar.layer.cornerRadius = 14;
    _inputBar.layer.borderWidth = 0.5;
    _inputBar.layer.borderColor = [WBFTheme line].CGColor;
    [self addSubview:_inputBar];

    _input = [[UITextField alloc] initWithFrame:CGRectZero];
    _input.delegate = self;
    _input.returnKeyType = UIReturnKeySend;
    _input.textColor = [WBFTheme txt];
    _input.font = [WBFTheme font:13 weight:UIFontWeightRegular];
    _input.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"描述你想让 AI 做的事…"
                                                                  attributes:@{NSForegroundColorAttributeName: [WBFTheme sub],
                                                                               NSFontAttributeName: [WBFTheme font:13 weight:UIFontWeightRegular]}];
    _input.tintColor = [WBFTheme accent];
    [_inputBar addSubview:_input];

    _sendBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _sendBtn.backgroundColor = [WBFTheme accent];
    _sendBtn.tintColor = [UIColor whiteColor];
    _sendBtn.layer.cornerRadius = 17;
    [_sendBtn setImage:[UIImage systemImageNamed:@"arrow.up"] forState:UIControlStateNormal];
    _sendBtn.imageEdgeInsets = UIEdgeInsetsMake(8, 8, 8, 8);
    [_sendBtn addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [_inputBar addSubview:_sendBtn];

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat barH = 52;
    _inputBar.frame = CGRectMake(10, h - barH - 6, w - 20, barH - 8);
    _input.frame = CGRectMake(12, 0, _inputBar.bounds.size.width - 62, _inputBar.bounds.size.height);
    _sendBtn.frame = CGRectMake(_inputBar.bounds.size.width - 44, (_inputBar.bounds.size.height - 34) / 2.0, 34, 34);
    _ctxLabel.frame = CGRectMake(14, CGRectGetMinY(_inputBar.frame) - 20, w - 90, 14);
    _progressBg.frame = CGRectMake(14, CGRectGetMinY(_ctxLabel.frame) - 6, w - 28, 2);
    _progressFill.frame = CGRectMake(0, 0, _progressBg.bounds.size.width * 0.0, 2);

    CGFloat scrollTop = 4;
    CGFloat scrollBottom = CGRectGetMinY(_progressBg.frame) - 6;
    _scroll.frame = CGRectMake(0, scrollTop, w, MAX(60, scrollBottom - scrollTop));
    _emptyHint.frame = CGRectMake(24, 40, w - 48, 90);
    [self relayoutBubbles];
}

- (void)relayoutBubbles {
    CGFloat w = _scroll.bounds.size.width;
    if (w < 10) w = self.bounds.size.width;
    CGFloat y = 10;
    for (WBFBubble *b in self.bubbles) {
        y = [b placeAtY:y width:w];
    }
    _stack.frame = CGRectMake(0, 0, w, MAX(y + 8, _scroll.bounds.size.height + 1));
    _scroll.contentSize = _stack.frame.size;
    _emptyHint.hidden = (self.bubbles.count > 0);
}

- (void)scrollToBottom {
    CGFloat maxY = _scroll.contentSize.height - _scroll.bounds.size.height;
    if (maxY < 0) maxY = 0;
    [_scroll setContentOffset:CGPointMake(0, maxY) animated:YES];
}

- (void)appendText:(NSString *)text kind:(WBFBubbleKind)kind {
    if (!text) return;
    CGFloat w = _scroll.bounds.size.width > 10 ? _scroll.bounds.size.width : self.bounds.size.width;
    if (w < 10) w = 360;
    WBFBubble *b = [[WBFBubble alloc] initWithText:text kind:kind maxWidth:w];
    [self.bubbles addObject:b];
    [_stack addSubview:b];
    [self relayoutBubbles];
    [self scrollToBottom];
}

- (void)clearAll {
    for (WBFBubble *b in self.bubbles) [b removeFromSuperview];
    [self.bubbles removeAllObjects];
    self.thinkingBubble = nil;
    [self relayoutBubbles];
    [self updateContextUsed:0 limit:[WBFConfig shared].maxContext step:0];
}

- (void)reloadHistory {
    if (self.bubbles.count) return;
    WBFTaskRecord *last = [[WBFConfig shared] history].firstObject;
    if (!last || !last.log.count) return;
    [self appendText:[NSString stringWithFormat:@"上次任务：%@", [last displayTitle]] kind:WBFBubbleInfo];
}

- (void)updateContextUsed:(NSInteger)used limit:(NSInteger)limit step:(NSInteger)step {
    NSString *txt = [NSString stringWithFormat:@"上下文 %@ / %@   ·   第 %ld 步",
                     WBFShortNumber(used), WBFShortNumber(limit), (long)step];
    self.ctxLabel.text = txt;
    CGFloat pct = limit > 0 ? MIN(1.0, (double)used / (double)limit) : 0;
    CGRect f = self.progressFill.frame;
    f.size.width = self.progressBg.bounds.size.width * pct;
    self.progressFill.frame = f;
    self.progressFill.backgroundColor = pct > 0.85 ? [WBFTheme danger] : (pct > 0.6 ? [WBFTheme warn] : [WBFTheme accent]);
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    [_sendBtn setImage:[UIImage systemImageNamed:busy ? @"stop.fill" : @"arrow.up"] forState:UIControlStateNormal];
    _sendBtn.backgroundColor = busy ? [WBFTheme danger] : [WBFTheme accent];
    _sendBtn.layer.cornerRadius = busy ? 6 : 17;
    _sendBtn.imageEdgeInsets = busy ? UIEdgeInsetsMake(10, 10, 10, 10) : UIEdgeInsetsMake(8, 8, 8, 8);
    if (!busy) [self removeThinking];
}

- (BOOL)isBusy { return _busy; }

- (void)removeThinking {
    if (self.thinkingBubble) {
        [self.thinkingBubble removeFromSuperview];
        [self.bubbles removeObject:self.thinkingBubble];
        self.thinkingBubble = nil;
        [self relayoutBubbles];
    }
}

- (void)handleEvent:(NSString *)type info:(NSDictionary *)info {
    if ([type isEqualToString:@"user"]) {
        [self appendText:info[@"text"] kind:WBFBubbleUser];
        [self setBusy:YES];
    } else if ([type isEqualToString:@"assistant"]) {
        [self removeThinking];
        [self appendText:info[@"text"] kind:WBFBubbleAssistant];
    } else if ([type isEqualToString:@"tool"]) {
        NSString *name = info[@"name"] ?: @"tool";
        NSString *state = info[@"state"] ?: @"";
        if ([state isEqualToString:@"running"]) {
            [self removeThinking];
            NSDictionary *args = info[@"args"];
            NSData *d = [NSJSONSerialization dataWithJSONObject:(args ?: @{}) options:0 error:NULL];
            NSString *argStr = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"";
            if (argStr.length > 120) argStr = [[argStr substringToIndex:120] stringByAppendingString:@"…"];
            [self appendText:[NSString stringWithFormat:@"⚙︎ %@  %@", name, argStr] kind:WBFBubbleTool];
        } else {
            NSString *res = info[@"result"] ?: @"";
            if (res.length > 420) res = [[res substringToIndex:420] stringByAppendingString:@"\n…"];
            [self appendText:res kind:WBFBubbleTool];
        }
    } else if ([type isEqualToString:@"thinking"]) {
        BOOL on = [info[@"on"] boolValue];
        if (on) {
            if (!self.thinkingBubble) {
                [self appendText:@"· 正在思考 ·" kind:WBFBubbleInfo];
                self.thinkingBubble = self.bubbles.lastObject;
            }
        } else {
            [self removeThinking];
        }
    } else if ([type isEqualToString:@"error"]) {
        [self removeThinking];
        [self appendText:[NSString stringWithFormat:@"⚠︎ %@", info[@"text"] ?: @"未知错误"] kind:WBFBubbleError];
        [self setBusy:NO];
    } else if ([type isEqualToString:@"truncated"]) {
        [self appendText:info[@"text"] ?: @"上下文已裁剪" kind:WBFBubbleInfo];
    } else if ([type isEqualToString:@"done"]) {
        [self removeThinking];
        NSString *status = info[@"status"] ?: @"done";
        NSString *text = info[@"text"] ?: @"任务结束";
        [self appendText:text kind:[status isEqualToString:@"failed"] ? WBFBubbleError : WBFBubbleAssistant];
        [self setBusy:NO];
        [self updateContextUsed:[[WBFAgent shared] usedTokens]
                          limit:[WBFConfig shared].maxContext
                           step:[[WBFAgent shared] step]];
    } else if ([type isEqualToString:@"tokens"]) {
        [self updateContextUsed:[info[@"used"] integerValue]
                          limit:[info[@"limit"] integerValue]
                           step:[info[@"step"] integerValue]];
    }
}

- (void)sendTapped {
    if (self.busy) {
        [[WBFAgent shared] stop];
        [self setBusy:NO];
        return;
    }
    NSString *t = WBFTrim(self.input.text);
    if (!t.length) {
        [self.input becomeFirstResponder];
        return;
    }
    self.input.text = @"";
    [self setBusy:YES];
    [[WBFAgent shared] startTask:t];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendTapped];
    return YES;
}

@end

#pragma mark - Terminal view

@interface WBFTerminalView () <UITextFieldDelegate>
@property (nonatomic, strong) UITextView *out;
@property (nonatomic, strong) UITextField *input;
@property (nonatomic, strong) UILabel *engine;
@property (nonatomic, strong) UIButton *send;
@property (nonatomic, strong) NSMutableArray *history;
@property (nonatomic, assign) NSInteger histIdx;
@property (nonatomic, assign) BOOL sessionTried;
@end

@implementation WBFTerminalView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [WBFTheme bg0];
    self.history = [NSMutableArray array];

    _engine = [[UILabel alloc] initWithFrame:CGRectZero];
    _engine.font = [WBFTheme mono:9];
    _engine.textColor = [WBFTheme sub];
    _engine.text = @"正在检测终端引擎…";
    [self addSubview:_engine];

    _out = [[UITextView alloc] initWithFrame:CGRectZero];
    _out.backgroundColor = [UIColor clearColor];
    _out.editable = NO;
    _out.textColor = WBFHexText();
    _out.font = [WBFTheme mono:11];
    _out.textContainerInset = UIEdgeInsetsMake(6, 10, 8, 10);
    _out.showsVerticalScrollIndicator = YES;
    [self addSubview:_out];

    _input = [[UITextField alloc] initWithFrame:CGRectZero];
    _input.delegate = self;
    _input.returnKeyType = UIReturnKeyGo;
    _input.autocorrectionType = UITextAutocorrectionTypeNo;
    _input.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _input.backgroundColor = [WBFTheme bg1];
    _input.textColor = [WBFTheme txt];
    _input.font = [WBFTheme mono:12];
    _input.layer.cornerRadius = 9;
    _input.leftView = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 22, 20)];
    ((UILabel *)_input.leftView).text = @"❯";
    ((UILabel *)_input.leftView).textColor = [WBFTheme accent];
    ((UILabel *)_input.leftView).font = [WBFTheme mono:12];
    ((UILabel *)_input.leftView).textAlignment = NSTextAlignmentCenter;
    _input.leftViewMode = UITextFieldViewModeAlways;
    _input.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"输入命令…"
                                                                  attributes:@{NSForegroundColorAttributeName: [WBFTheme sub]}];
    [self addSubview:_input];

    _send = [UIButton buttonWithType:UIButtonTypeSystem];
    _send.backgroundColor = [WBFTheme bg2];
    _send.tintColor = [WBFTheme accent];
    _send.layer.cornerRadius = 9;
    [_send setImage:[UIImage systemImageNamed:@"arrow.right"] forState:UIControlStateNormal];
    [_send addTarget:self action:@selector(runInput) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_send];

    NSArray *keys = @[@"↑", @"⇥", @"⌃C", @"清屏"];
    CGFloat kx = 0;
    CGFloat kw = 0;
    for (NSString *k in keys) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:k forState:UIControlStateNormal];
        [b setTitleColor:[WBFTheme sub] forState:UIControlStateNormal];
        b.titleLabel.font = [WBFTheme mono:10];
        b.backgroundColor = [WBFTheme bg1];
        b.layer.cornerRadius = 7;
        [b addTarget:self action:@selector(quickKey:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
        kx += 1;
        kw += 1;
    }
    [self appendOutput:@"WBF 终端 · 真实命令执行\n输入 help 查看内置命令；安装 root 守护进程可获得完整 root shell。\n\n"];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    _engine.frame = CGRectMake(14, 6, w - 28, 12);
    _input.frame = CGRectMake(12, h - 46, w - 24 - 46, 36);
    _send.frame = CGRectMake(CGRectGetMaxX(_input.frame) + 8, h - 46, 38, 36);
    CGFloat ky = h - 46 - 34;
    CGFloat kwid = (w - 24 - 12) / 4.0;
    NSInteger i = 0;
    for (UIView *v in self.subviews) {
        if ([v isKindOfClass:[UIButton class]] && v != _send) {
            v.frame = CGRectMake(12 + (kwid + 4) * i, ky, kwid, 28);
            i++;
        }
    }
    _out.frame = CGRectMake(0, 22, w, MAX(40, ky - 26));
}

- (void)appendOutput:(NSString *)text {
    if (!text) return;
    NSString *cur = self.out.text ?: @"";
    if (cur.length > 60000) cur = [cur substringFromIndex:cur.length - 40000];
    self.out.text = [cur stringByAppendingString:text];
    if (self.out.text.length > 0) {
        NSRange r = NSMakeRange(self.out.text.length - 1, 1);
        [self.out scrollRangeToVisible:r];
    }
}

- (void)activateSession {
    if (self.sessionTried) {
        [self updateEngineLabel];
        return;
    }
    self.sessionTried = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        BOOL daemon = [[WBFShell shared] daemonAvailable];
        BOOL ok = NO;
        if (daemon) ok = [[WBFShell shared] openSession];
        WBFDispatchMain(^{
            [weakSelf updateEngineLabel];
            if (ok) [weakSelf appendOutput:@"[已连接 root 守护进程，交互式 shell 就绪]\n"];
            else if (daemon) [weakSelf appendOutput:@"[守护进程在但会话未建立，命令将单次执行]\n"];
            else [weakSelf appendOutput:@"[未检测到 root 守护进程，命令将走沙盒内 sh / 内置命令]\n"];
        });
    });
}

- (void)updateEngineLabel {
    self.engine.text = [NSString stringWithFormat:@"引擎: %@", [[WBFShell shared] engineName]];
}

- (void)runInput {
    NSString *cmd = WBFTrim(self.input.text);
    if (!cmd.length) return;
    self.input.text = @"";
    [self.history addObject:cmd];
    self.histIdx = (NSInteger)self.history.count;
    [self appendOutput:[NSString stringWithFormat:@"❯ %@\n", cmd]];

    WBFShell *sh = [WBFShell shared];
    if ([sh sessionOpen]) {
        [sh sendInput:[cmd stringByAppendingString:@"\n"]];
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSString *outStr = [sh exec:cmd timeout:20];
        if (!outStr.length) outStr = @"";
        WBFDispatchMain(^{ [weakSelf appendOutput:outStr]; });
    });
}

- (void)quickKey:(UIButton *)b {
    NSString *t = b.titleLabel.text;
    WBFShell *sh = [WBFShell shared];
    if ([t isEqualToString:@"清屏"]) { self.out.text = @""; return; }
    if ([sh sessionOpen]) {
        if ([t isEqualToString:@"↑"]) [sh sendInput:@"\u001b[A"];
        else if ([t isEqualToString:@"⇥"]) [sh sendInput:@"\t"];
        else if ([t isEqualToString:@"⌃C"]) [sh sendInput:@"\u0003"];
        return;
    }
    if ([t isEqualToString:@"↑"]) {
        if (!self.history.count) return;
        self.histIdx = MAX(0, self.histIdx - 1);
        self.input.text = self.history[(NSUInteger)MIN(self.histIdx, (NSInteger)self.history.count - 1)];
    } else if ([t isEqualToString:@"⌃C"]) {
        self.input.text = @"";
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self runInput];
    return YES;
}

@end

#pragma mark - Tools view

@interface WBFToolsView ()
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UITextView *out;
@property (nonatomic, strong) NSMutableArray *rows;
@end

@implementation WBFToolsView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [WBFTheme bg0];
    self.rows = [NSMutableArray array];

    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scroll.showsVerticalScrollIndicator = NO;
    [self addSubview:_scroll];

    _out = [[UITextView alloc] initWithFrame:CGRectZero];
    _out.backgroundColor = [WBFTheme bg1];
    _out.editable = NO;
    _out.textColor = [WBFTheme sub];
    _out.font = [WBFTheme mono:10];
    _out.layer.cornerRadius = 10;
    _out.textContainerInset = UIEdgeInsetsMake(8, 10, 8, 10);
    _out.text = @"工具返回结果会显示在这里。";
    [self addSubview:_out];

    NSArray *items = @[
        @[@"camera.viewfinder", @"截图当前界面", @"screenshot", @{}],
        @[@"list.bullet.rectangle", @"导出界面结构", @"ui_tree", @{}],
        @[@"doc.on.clipboard", @"读取剪贴板", @"clipboard", @{@"action": @"get"}],
        @[@"square.and.arrow.down", @"写入剪贴板", @"clipboard", @{@"action": @"set", @"text": @"WBF"}],
        @[@"square.grid.2x2", @"已安装应用", @"list_apps", @{}],
        @[@"iphone", @"设备与引擎信息", @"app_info", @{}],
        @[@"folder", @"列出 /var/mobile", @"shell", @{@"command": @"ls -la /var/mobile"}],
        @[@"terminal", @"查看进程", @"shell", @{@"command": @"ps aux | head -30"}]
    ];
    NSInteger idx = 0;
    for (NSArray *it in items) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = idx++;
        b.backgroundColor = [WBFTheme bg1];
        b.layer.cornerRadius = 10;
        b.layer.borderWidth = 0.5;
        b.layer.borderColor = [WBFTheme line].CGColor;

        UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:it[0]]];
        iv.tintColor = [WBFTheme accent];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.tag = 101;
        [b addSubview:iv];

        UILabel *lb = [[UILabel alloc] initWithFrame:CGRectZero];
        lb.text = it[1];
        lb.textColor = [WBFTheme txt];
        lb.font = [WBFTheme font:12 weight:UIFontWeightMedium];
        lb.tag = 102;
        [b addSubview:lb];

        UIView *chev = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        ((UIImageView *)chev).tintColor = [WBFTheme bg3];
        chev.tag = 103;
        [b addSubview:chev];

        [b addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_scroll addSubview:b];
        [self.rows addObject:@{@"view": b, @"tool": it[2], @"args": it[3]}];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat rowH = 44;
    CGFloat y = 6;
    for (NSDictionary *d in self.rows) {
        UIButton *b = d[@"view"];
        b.frame = CGRectMake(12, y, w - 24, rowH);
        UIImageView *iv = [b viewWithTag:101];
        iv.frame = CGRectMake(12, (rowH - 18) / 2.0, 18, 18);
        UILabel *lb = [b viewWithTag:102];
        lb.frame = CGRectMake(40, 0, w - 24 - 80, rowH);
        UIView *chev = [b viewWithTag:103];
        chev.frame = CGRectMake(w - 24 - 26, (rowH - 12) / 2.0, 12, 12);
        y += rowH + 6;
    }
    _scroll.frame = CGRectMake(0, 0, w, y + 2);
    _out.frame = CGRectMake(12, y + 8, w - 24, MAX(60, h - y - 14));
}

- (void)rowTapped:(UIButton *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= (NSInteger)self.rows.count) return;
    NSDictionary *d = self.rows[(NSUInteger)idx];
    [self runToolNamed:d[@"tool"] args:d[@"args"]];
}

- (void)runToolNamed:(NSString *)name args:(NSDictionary *)args {
    self.out.text = [NSString stringWithFormat:@"执行 %@ …\n", name];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSString *res = [[WBFTools shared] execute:name arguments:args];
        NSArray *imgs = [NSArray arrayWithArray:[WBFTools shared].pendingImages];
        [[WBFTools shared].pendingImages removeAllObjects];
        WBFDispatchMain(^{
            NSString *txt = res ?: @"";
            if (imgs.count) txt = [txt stringByAppendingFormat:@"\n\n[已生成截图 %lu 张]", (unsigned long)imgs.count];
            weakSelf.out.text = txt;
        });
    });
}

@end

#pragma mark - Settings view

@interface WBFSettingsView () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UITextField *urlField;
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, strong) UITextField *ctxField;
@property (nonatomic, strong) UITextField *stepsField;
@property (nonatomic, strong) UITextField *maxTokField;
@property (nonatomic, strong) UIButton *modelBtn;
@property (nonatomic, strong) UILabel *engineLabel;
@property (nonatomic, strong) UILabel *tempLabel;
@property (nonatomic, strong) UISlider *tempSlider;
@property (nonatomic, strong) UISlider *opacitySlider;
@property (nonatomic, strong) UISegmentedControl *inputSeg;
@property (nonatomic, strong) UISwitch *shotSwitch;
@property (nonatomic, strong) UISwitch *dangerSwitch;
@property (nonatomic, strong) UILabel *probeLabel;
@property (nonatomic, assign) CGFloat cursorY;
@end

@implementation WBFSettingsView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [WBFTheme bg0];
    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _scroll.alwaysBounceVertical = YES;
    [self addSubview:_scroll];
    [self build];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _scroll.frame = self.bounds;
    _scroll.contentSize = CGSizeMake(self.bounds.size.width, self.cursorY + 20);
    CGFloat w = self.bounds.size.width;
    for (UIView *v in _scroll.subviews) {
        if (v.tag == 777 && [v isKindOfClass:[UILabel class]]) {
            CGRect r = v.frame;
            r.size.width = w - 32;
            v.frame = r;
        }
        if (v.tag == 778) {
            CGRect r = v.frame;
            r.size.width = w - 24;
            v.frame = r;
        }
        if ([v isKindOfClass:[UITextField class]] && v.tag != 999) {
            CGFloat x = CGRectGetMinX(v.frame);
            CGFloat fw = w - x - 16;
            if (fw > 120) {
                CGRect r = v.frame;
                r.size.width = fw;
                v.frame = r;
            }
        }
    }
}

- (UILabel *)title:(NSString *)t {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = t;
    l.font = [WBFTheme font:10.5 weight:UIFontWeightSemibold];
    l.textColor = [WBFTheme sub];
    l.tag = 777;
    return l;
}

- (UITextField *)field:(NSString *)ph secure:(BOOL)secure {
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectZero];
    f.backgroundColor = [WBFTheme bg1];
    f.textColor = [WBFTheme txt];
    f.font = [WBFTheme mono:11.5];
    f.layer.cornerRadius = 9;
    f.layer.borderWidth = 0.5;
    f.layer.borderColor = [WBFTheme line].CGColor;
    f.secureTextEntry = secure;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.attributedPlaceholder = [[NSAttributedString alloc] initWithString:(ph ?: @"")
                                                              attributes:@{NSForegroundColorAttributeName: [WBFTheme bg3],
                                                                           NSFontAttributeName: [WBFTheme mono:11.5]}];
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 1)];
    f.leftView = pad;
    f.leftViewMode = UITextFieldViewModeAlways;
    f.delegate = self;
    f.tag = 999;
    return f;
}

- (void)build {
    WBFConfig *cfg = [WBFConfig shared];
    CGFloat w = 360;
    CGFloat y = 12;

    // ---- 服务商
    UILabel *s1 = [self title:@"服务商预设"];
    s1.frame = CGRectMake(16, y, w, 14);
    [_scroll addSubview:s1];
    y += 20;
    NSArray *presets = @[@"OpenAI", @"DeepSeek", @"OpenRouter", @"本地"];
    CGFloat px = 16;
    for (NSInteger i = 0; i < presets.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:presets[i] forState:UIControlStateNormal];
        b.titleLabel.font = [WBFTheme font:11 weight:UIFontWeightMedium];
        b.tag = 100 + i;
        b.backgroundColor = [WBFTheme bg1];
        [b setTitleColor:[WBFTheme sub] forState:UIControlStateNormal];
        b.layer.cornerRadius = 8;
        b.layer.borderWidth = 0.5;
        b.layer.borderColor = [WBFTheme line].CGColor;
        b.frame = CGRectMake(px, y, 74, 30);
        [b addTarget:self action:@selector(presetTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_scroll addSubview:b];
        px += 78;
    }
    y += 40;

    // ---- Base URL
    UILabel *s2 = [self title:@"API Base URL"];
    s2.frame = CGRectMake(16, y, w, 14);
    [_scroll addSubview:s2];
    y += 18;
    _urlField = [self field:@"https://api.openai.com/v1" secure:NO];
    _urlField.frame = CGRectMake(16, y, w - 32, 36);
    _urlField.text = cfg.baseURL;
    [_urlField addTarget:self action:@selector(urlChanged) forControlEvents:UIControlEventEditingChanged];
    [_scroll addSubview:_urlField];
    y += 44;

    // ---- Key
    UILabel *s3 = [self title:@"API Key（本机缓存，不会外传）"];
    s3.frame = CGRectMake(16, y, w, 14);
    [_scroll addSubview:s3];
    y += 18;
    _keyField = [self field:@"sk-..." secure:YES];
    _keyField.frame = CGRectMake(16, y, w - 32, 36);
    _keyField.text = cfg.apiKey;
    [_keyField addTarget:self action:@selector(keyChanged) forControlEvents:UIControlEventEditingChanged];
    [_scroll addSubview:_keyField];
    y += 44;

    // ---- 模型
    UILabel *s4 = [self title:@"模型"];
    s4.frame = CGRectMake(16, y, w, 14);
    [_scroll addSubview:s4];
    y += 18;
    UIButton *modelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    modelBtn.backgroundColor = [WBFTheme bg1];
    modelBtn.layer.cornerRadius = 9;
    modelBtn.layer.borderWidth = 0.5;
    modelBtn.layer.borderColor = [WBFTheme line].CGColor;
    modelBtn.frame = CGRectMake(16, y, w - 32 - 96, 36);
    modelBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    modelBtn.titleEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
    [modelBtn setTitle:cfg.model ?: @"选择模型" forState:UIControlStateNormal];
    [modelBtn setTitleColor:[WBFTheme txt] forState:UIControlStateNormal];
    modelBtn.titleLabel.font = [WBFTheme mono:11.5];
    [modelBtn addTarget:self action:@selector(modelTapped) forControlEvents:UIControlEventTouchUpInside];
    _modelBtn = modelBtn;
    [_scroll addSubview:modelBtn];

    UIButton *fetchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    fetchBtn.backgroundColor = [WBFTheme bg2];
    fetchBtn.layer.cornerRadius = 9;
    [fetchBtn setTitle:@"拉取列表" forState:UIControlStateNormal];
    [fetchBtn setTitleColor:[WBFTheme accent] forState:UIControlStateNormal];
    fetchBtn.titleLabel.font = [WBFTheme font:11.5 weight:UIFontWeightMedium];
    fetchBtn.frame = CGRectMake(CGRectGetMaxX(modelBtn.frame) + 8, y, 88, 36);
    [fetchBtn addTarget:self action:@selector(fetchModels) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:fetchBtn];
    y += 44;

    // ---- 上下文
    UILabel *s5 = [self title:@"最大上下文 (tokens)"];
    s5.frame = CGRectMake(16, y, w, 14);
    [_scroll addSubview:s5];
    y += 18;
    _ctxField = [self field:@"128000" secure:NO];
    _ctxField.keyboardType = UIKeyboardTypeNumberPad;
    _ctxField.frame = CGRectMake(16, y, w - 32, 36);
    _ctxField.text = [NSString stringWithFormat:@"%ld", (long)cfg.maxContext];
    [_ctxField addTarget:self action:@selector(ctxChanged) forControlEvents:UIControlEventEditingChanged];
    [_scroll addSubview:_ctxField];
    y += 42;
    NSArray *ctxPresets = @[@"8k", @"32k", @"128k", @"200k"];
    px = 16;
    for (NSInteger i = 0; i < ctxPresets.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:ctxPresets[i] forState:UIControlStateNormal];
        b.titleLabel.font = [WBFTheme font:11 weight:UIFontWeightMedium];
        b.tag = 200 + i;
        b.backgroundColor = [WBFTheme bg1];
        [b setTitleColor:[WBFTheme sub] forState:UIControlStateNormal];
        b.layer.cornerRadius = 7;
        b.frame = CGRectMake(px, y, 58, 28);
        [b addTarget:self action:@selector(ctxPreset:) forControlEvents:UIControlEventTouchUpInside];
        [_scroll addSubview:b];
        px += 62;
    }
    y += 38;

    // ---- 输入类型
    UILabel *s6 = [self title:@"输入类型"];
    s6.frame = CGRectMake(16, y, w, 14);
    [_scroll addSubview:s6];
    y += 18;
    _inputSeg = [[UISegmentedControl alloc] initWithItems:@[@"纯文本", @"文本+截图", @"文本+界面树"]];
    _inputSeg.frame = CGRectMake(16, y, w - 32, 32);
    _inputSeg.selectedSegmentIndex = MIN(2, MAX(0, cfg.inputMode));
    _inputSeg.tag = 300;
    if (@available(iOS 13.0, *)) {
        _inputSeg.selectedSegmentTintColor = [WBFTheme accent];
    }
    _inputSeg.tintColor = [WBFTheme accent];
    NSDictionary *normalAttr = @{NSForegroundColorAttributeName: [WBFTheme sub],
                                 NSFontAttributeName: [WBFTheme font:10.5 weight:UIFontWeightMedium]};
    NSDictionary *selAttr = @{NSForegroundColorAttributeName: [UIColor whiteColor],
                              NSFontAttributeName: [WBFTheme font:10.5 weight:UIFontWeightSemibold]};
    [_inputSeg setTitleTextAttributes:normalAttr forState:UIControlStateNormal];
    [_inputSeg setTitleTextAttributes:selAttr forState:UIControlStateSelected];
    [_inputSeg addTarget:self action:@selector(inputModeChanged) forControlEvents:UIControlEventValueChanged];
    [_scroll addSubview:_inputSeg];
    y += 42;

    // ---- 温度
    UILabel *s7 = [self title:@"温度"];
    s7.frame = CGRectMake(16, y, w, 14);
    [_scroll addSubview:s7];
    _tempLabel = [[UILabel alloc] initWithFrame:CGRectMake(w - 70, y, 54, 14)];
    _tempLabel.textAlignment = NSTextAlignmentRight;
    _tempLabel.font = [WBFTheme mono:10];
    _tempLabel.textColor = [WBFTheme accent];
    _tempLabel.text = [NSString stringWithFormat:@"%.2f", cfg.temperature];
    [_scroll addSubview:_tempLabel];
    y += 18;
    _tempSlider = [[UISlider alloc] initWithFrame:CGRectMake(16, y, w - 32, 28)];
    _tempSlider.minimumValue = 0.0;
    _tempSlider.maximumValue = 1.5;
    _tempSlider.value = (float)cfg.temperature;
    _tempSlider.minimumTrackTintColor = [WBFTheme accent];
    _tempSlider.maximumTrackTintColor = [WBFTheme bg3];
    [_tempSlider addTarget:self action:@selector(tempChanged) forControlEvents:UIControlEventValueChanged];
    [_scroll addSubview:_tempSlider];
    y += 36;

    // ---- 步数 / 回复上限
    CGFloat halfW = (w - 32 - 10) / 2.0;
    UILabel *s8 = [self title:@"最大步数"];
    s8.frame = CGRectMake(16, y, halfW, 14);
    [_scroll addSubview:s8];
    UILabel *s9 = [self title:@"单次回复上限"];
    s9.frame = CGRectMake(16 + halfW + 10, y, halfW, 14);
    [_scroll addSubview:s9];
    y += 18;
    _stepsField = [self field:@"30" secure:NO];
    _stepsField.keyboardType = UIKeyboardTypeNumberPad;
    _stepsField.frame = CGRectMake(16, y, halfW, 34);
    _stepsField.text = [NSString stringWithFormat:@"%ld", (long)cfg.maxSteps];
    [_stepsField addTarget:self action:@selector(stepsChanged) forControlEvents:UIControlEventEditingChanged];
    [_scroll addSubview:_stepsField];
    _maxTokField = [self field:@"0 = 自动" secure:NO];
    _maxTokField.keyboardType = UIKeyboardTypeNumberPad;
    _maxTokField.frame = CGRectMake(16 + halfW + 10, y, halfW, 34);
    _maxTokField.text = cfg.maxTokens > 0 ? [NSString stringWithFormat:@"%ld", (long)cfg.maxTokens] : @"";
    [_maxTokField addTarget:self action:@selector(maxTokChanged) forControlEvents:UIControlEventEditingChanged];
    [_scroll addSubview:_maxTokField];
    y += 44;

    // ---- 开关
    _shotSwitch = [self switchRow:@"每步自动附带截图" y:y action:@selector(shotChanged) on:cfg.sendScreenshot];
    y += 40;
    _dangerSwitch = [self switchRow:@"危险命令执行前确认" y:y action:@selector(dangerChanged) on:cfg.confirmDanger];
    y += 40;

    // ---- 透明度
    UILabel *s10 = [self title:@"悬浮球透明度"];
    s10.frame = CGRectMake(16, y, w, 14);
    [_scroll addSubview:s10];
    y += 18;
    _opacitySlider = [[UISlider alloc] initWithFrame:CGRectMake(16, y, w - 32, 28)];
    _opacitySlider.minimumValue = 0.25;
    _opacitySlider.maximumValue = 1.0;
    _opacitySlider.value = (float)cfg.ballOpacity;
    _opacitySlider.minimumTrackTintColor = [WBFTheme accent];
    _opacitySlider.maximumTrackTintColor = [WBFTheme bg3];
    [_opacitySlider addTarget:self action:@selector(opacityChanged) forControlEvents:UIControlEventValueChanged];
    [_scroll addSubview:_opacitySlider];
    y += 36;

    // ---- 测试连接
    UIButton *probe = [UIButton buttonWithType:UIButtonTypeSystem];
    probe.backgroundColor = [WBFTheme bg2];
    probe.layer.cornerRadius = 10;
    [probe setTitle:@"测试连通性" forState:UIControlStateNormal];
    [probe setTitleColor:[WBFTheme txt] forState:UIControlStateNormal];
    probe.titleLabel.font = [WBFTheme font:12.5 weight:UIFontWeightSemibold];
    probe.frame = CGRectMake(16, y, w - 32, 40);
    [probe addTarget:self action:@selector(probeTapped) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:probe];
    y += 50;

    _probeLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 30)];
    _probeLabel.numberOfLines = 0;
    _probeLabel.font = [WBFTheme font:10.5 weight:UIFontWeightRegular];
    _probeLabel.textColor = [WBFTheme sub];
    _probeLabel.tag = 778;
    [_scroll addSubview:_probeLabel];
    y += 36;

    _engineLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, y, w - 32, 46)];
    _engineLabel.numberOfLines = 0;
    _engineLabel.font = [WBFTheme mono:9.5];
    _engineLabel.textColor = [WBFTheme sub];
    _engineLabel.tag = 778;
    [_scroll addSubview:_engineLabel];
    y += 56;

    self.cursorY = y;
    [self reload];
}

- (UISwitch *)switchRow:(NSString *)title y:(CGFloat)y action:(SEL)action on:(BOOL)on {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(12, y, 340, 34)];
    row.backgroundColor = [WBFTheme bg1];
    row.layer.cornerRadius = 9;
    row.tag = 778;
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(14, 0, 260, 34)];
    l.text = title;
    l.textColor = [WBFTheme txt];
    l.font = [WBFTheme font:12 weight:UIFontWeightRegular];
    [row addSubview:l];
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(290, 3, 51, 31)];
    sw.onTintColor = [WBFTheme accent];
    sw.on = on;
    sw.transform = CGAffineTransformMakeScale(0.78, 0.78);
    sw.tag = 500;
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];
    [_scroll addSubview:row];
    return sw;
}

- (void)layoutSwitchRows {
    CGFloat w = self.bounds.size.width;
    for (UIView *v in _scroll.subviews) {
        if (v.tag == 778) {
            CGRect r = v.frame;
            r.size.width = w - 24;
            v.frame = r;
            UIView *sw = [v viewWithTag:500];
            if (sw) sw.frame = CGRectMake(r.size.width - 62, 3, 51, 31);
        }
    }
}

- (void)reload {
    WBFConfig *cfg = [WBFConfig shared];
    _urlField.text = cfg.baseURL;
    _keyField.text = cfg.apiKey;
    _ctxField.text = [NSString stringWithFormat:@"%ld", (long)cfg.maxContext];
    _stepsField.text = [NSString stringWithFormat:@"%ld", (long)cfg.maxSteps];
    _maxTokField.text = cfg.maxTokens > 0 ? [NSString stringWithFormat:@"%ld", (long)cfg.maxTokens] : @"";
    [_modelBtn setTitle:(cfg.model ?: @"选择模型") forState:UIControlStateNormal];
    _shotSwitch.on = cfg.sendScreenshot;
    _dangerSwitch.on = cfg.confirmDanger;
    _inputSeg.selectedSegmentIndex = MIN(2, MAX(0, cfg.inputMode));
    _tempSlider.value = (float)cfg.temperature;
    _tempLabel.text = [NSString stringWithFormat:@"%.2f", cfg.temperature];
    _engineLabel.text = [NSString stringWithFormat:@"触摸: %@\n终端: %@", [WBFTouch engineName], [[WBFShell shared] engineName]];
    [self layoutSwitchRows];
}

#pragma mark - actions

- (void)presetTapped:(UIButton *)b {
    NSInteger idx = b.tag - 100;
    NSArray *urls = @[@"https://api.openai.com/v1",
                      @"https://api.deepseek.com/v1",
                      @"https://openrouter.ai/api/v1",
                      @"http://127.0.0.1:1234/v1"];
    NSArray *models = @[@"gpt-4o", @"deepseek-chat", @"anthropic/claude-3.5-sonnet", @"local-model"];
    if (idx < 0 || idx >= (NSInteger)urls.count) return;
    WBFConfig *cfg = [WBFConfig shared];
    cfg.baseURL = urls[(NSUInteger)idx];
    cfg.model = models[(NSUInteger)idx];
    [cfg save];
    [self reload];
}

- (void)urlChanged {
    [WBFConfig shared].baseURL = WBFTrim(_urlField.text);
    [[WBFConfig shared] save];
}

- (void)keyChanged {
    [WBFConfig shared].apiKey = WBFTrim(_keyField.text);
    [[WBFConfig shared] save];
}

- (void)ctxChanged {
    NSInteger v = _ctxField.text.integerValue;
    if (v > 0) {
        [WBFConfig shared].maxContext = v;
        [[WBFConfig shared] save];
    }
}

- (void)ctxPreset:(UIButton *)b {
    NSArray *vals = @[@8000, @32000, @128000, @200000];
    NSInteger idx = b.tag - 200;
    if (idx < 0 || idx >= (NSInteger)vals.count) return;
    [WBFConfig shared].maxContext = [vals[(NSUInteger)idx] integerValue];
    [[WBFConfig shared] save];
    _ctxField.text = [NSString stringWithFormat:@"%ld", (long)[WBFConfig shared].maxContext];
}

- (void)stepsChanged {
    NSInteger v = _stepsField.text.integerValue;
    [WBFConfig shared].maxSteps = MAX(1, MIN(120, v));
    [[WBFConfig shared] save];
}

- (void)maxTokChanged {
    [WBFConfig shared].maxTokens = MAX(0, _maxTokField.text.integerValue);
    [[WBFConfig shared] save];
}

- (void)tempChanged {
    [WBFConfig shared].temperature = _tempSlider.value;
    _tempLabel.text = [NSString stringWithFormat:@"%.2f", _tempSlider.value];
    [[WBFConfig shared] save];
}

- (void)shotChanged {
    [WBFConfig shared].sendScreenshot = _shotSwitch.on;
    [[WBFConfig shared] save];
}

- (void)dangerChanged {
    [WBFConfig shared].confirmDanger = _dangerSwitch.on;
    [[WBFConfig shared] save];
}

- (void)opacityChanged {
    [WBFConfig shared].ballOpacity = _opacitySlider.value;
    [[WBFConfig shared] save];
}

- (void)inputModeChanged {
    [WBFConfig shared].inputMode = _inputSeg.selectedSegmentIndex;
    [[WBFConfig shared] save];
}

- (void)modelTapped {
    WBFConfig *cfg = [WBFConfig shared];
    NSArray *list = cfg.modelList;
    if (!list.count) {
        list = @[@"gpt-4o", @"gpt-4o-mini", @"gpt-4.1", @"deepseek-chat", @"deepseek-reasoner",
                 @"claude-3.5-sonnet", @"gemini-1.5-pro", @"qwen-max", @"glm-4-plus"];
    }
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"选择模型" message:nil
                                                        preferredStyle:UIAlertControllerStyleActionSheet];
    NSInteger n = 0;
    for (NSString *m in list) {
        if (n++ > 40) break;
        [ac addAction:[UIAlertAction actionWithTitle:m style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [WBFConfig shared].model = m;
            [[WBFConfig shared] save];
            [self reload];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UIViewController *top = self.wbf_viewController;
    [top presentViewController:ac animated:YES completion:nil];
}

- (UIViewController *)wbf_viewController {
    UIResponder *r = self;
    while (r) {
        if ([r isKindOfClass:[UIViewController class]]) return (UIViewController *)r;
        r = r.nextResponder;
    }
    return nil;
}

- (void)fetchModels {
    self.probeLabel.textColor = [WBFTheme sub];
    self.probeLabel.text = @"正在拉取模型列表…";
    __weak typeof(self) weakSelf = self;
    [[WBFLLM shared] fetchModels:^(NSArray<NSString *> *models, NSError *error) {
        WBFDispatchMain(^{
            if (error || !models.count) {
                weakSelf.probeLabel.textColor = [WBFTheme danger];
                weakSelf.probeLabel.text = [NSString stringWithFormat:@"拉取失败：%@", error.localizedDescription ?: @"空列表"];
                return;
            }
            [WBFConfig shared].modelList = models;
            [[WBFConfig shared] save];
            weakSelf.probeLabel.textColor = [WBFTheme ok];
            weakSelf.probeLabel.text = [NSString stringWithFormat:@"已获取 %lu 个模型，点上方按钮选择", (unsigned long)models.count];
        });
    }];
}

- (void)probeTapped {
    self.probeLabel.textColor = [WBFTheme warn];
    self.probeLabel.text = @"正在测试…";
    __weak typeof(self) weakSelf = self;
    [[WBFLLM shared] probe:^(NSString *summary) {
        WBFDispatchMain(^{
            BOOL bad = [summary hasPrefix:@"失败"];
            weakSelf.probeLabel.textColor = bad ? [WBFTheme danger] : [WBFTheme ok];
            weakSelf.probeLabel.text = summary;
        });
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
