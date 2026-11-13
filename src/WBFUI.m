//
//  WBFUI.m
//  Floating ball + panel shell
//

#import "WBFUI.h"
#import "WBFInternal.h"
#import "WBFAgent.h"
#import "WBFTools.h"
#import "WBFTouch.h"
#import "WBFShell.h"
#import "WBFLLM.h"

#pragma mark - Theme

static UIColor *WBFHex(NSUInteger v) {
    return [UIColor colorWithRed:(CGFloat)((v >> 16) & 0xFF) / 255.0
                           green:(CGFloat)((v >> 8) & 0xFF) / 255.0
                            blue:(CGFloat)(v & 0xFF) / 255.0
                           alpha:1.0];
}

@implementation WBFTheme
+ (UIColor *)bg0 { return WBFHex(0x0A0D12); }
+ (UIColor *)bg1 { return WBFHex(0x141922); }
+ (UIColor *)bg2 { return WBFHex(0x1D242F); }
+ (UIColor *)bg3 { return WBFHex(0x28313F); }
+ (UIColor *)line { return WBFHex(0x2B3442); }
+ (UIColor *)txt { return WBFHex(0xE9EEF7); }
+ (UIColor *)sub { return WBFHex(0x8E9BAF); }
+ (UIColor *)accent { return WBFHex(0x4C8DFF); }
+ (UIColor *)accent2 { return WBFHex(0x8B5CF6); }
+ (UIColor *)ok { return WBFHex(0x2FD39B); }
+ (UIColor *)warn { return WBFHex(0xFFB020); }
+ (UIColor *)danger { return WBFHex(0xFF5D5D); }
+ (UIFont *)font:(CGFloat)size weight:(UIFontWeight)weight {
    UIFont *f = [UIFont systemFontOfSize:size weight:weight];
    return f ?: [UIFont systemFontOfSize:size];
}
+ (UIFont *)mono:(CGFloat)size {
    UIFont *f = [UIFont fontWithName:@"Menlo-Regular" size:size];
    if (!f) f = [UIFont fontWithName:@"Courier" size:size];
    if (!f) f = [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightRegular];
    return f;
}
@end

#pragma mark - Bubble

@implementation WBFBubble {
    UILabel *_label;
    WBFBubbleKind _kind;
    CGFloat _bw;
}

- (instancetype)initWithText:(NSString *)text kind:(WBFBubbleKind)kind maxWidth:(CGFloat)maxW {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _kind = kind;
    NSString *t = text ?: @"";
    BOOL mono = (kind == WBFBubbleTool);
    CGFloat fs = mono ? 10.5 : (kind == WBFBubbleInfo ? 11.0 : 13.5);
    UIFont *font = mono ? [WBFTheme mono:fs] : [WBFTheme font:fs weight:UIFontWeightRegular];

    CGFloat textMax = MAX(80.0, maxW * 0.84 - 22.0);
    CGRect r = [t boundingRectWithSize:CGSizeMake(textMax, CGFLOAT_MAX)
                               options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                            attributes:@{NSFontAttributeName: font}
                               context:nil];
    CGFloat tw = ceil(r.size.width) + 2;
    CGFloat th = ceil(r.size.height) + 2;
    _bw = MIN(maxW * 0.84, tw + 20.0);
    if (_bw < 40) _bw = 40;
    self.bubbleHeight = th + 16.0;

    _label = [[UILabel alloc] initWithFrame:CGRectMake(10, 8, _bw - 20, th)];
    _label.font = font;
    _label.numberOfLines = 0;
    _label.text = t;
    [self addSubview:_label];

    UIColor *bg = [WBFTheme bg1];
    UIColor *fg = [WBFTheme txt];
    if (kind == WBFBubbleUser) { bg = [WBFTheme accent]; fg = [UIColor whiteColor]; }
    else if (kind == WBFBubbleTool) { bg = [WBFTheme bg2]; fg = [WBFTheme sub]; }
    else if (kind == WBFBubbleError) { bg = [[WBFTheme danger] colorWithAlphaComponent:0.16]; fg = WBFHex(0xFFB4B4); }
    else if (kind == WBFBubbleInfo) { bg = [UIColor clearColor]; fg = [WBFTheme sub]; }
    if (kind == WBFBubbleInfo) {
        _label.textAlignment = NSTextAlignmentCenter;
        _label.frame = CGRectMake(0, 4, maxW, th);
        _bw = maxW;
        self.bubbleHeight = th + 12;
        self.backgroundColor = [UIColor clearColor];
    } else {
        self.backgroundColor = bg;
        self.layer.cornerRadius = 13;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        if (kind == WBFBubbleTool) {
            self.layer.borderWidth = 0.5;
            self.layer.borderColor = [WBFTheme line].CGColor;
        }
    }
    _label.textColor = fg;
    self.layer.masksToBounds = YES;
    return self;
}

- (CGFloat)placeAtY:(CGFloat)y width:(CGFloat)w {
    CGFloat x;
    if (_kind == WBFBubbleUser) x = w - 12 - _bw;
    else if (_kind == WBFBubbleInfo) x = 0;
    else x = 12;
    self.frame = CGRectMake(x, y, _bw, self.bubbleHeight);
    return y + self.bubbleHeight + 6;
}

@end

#pragma mark - Panel

@interface WBFPanelView ()
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) UIView *tabBar;
@property (nonatomic, strong) UIView *content;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIView *indicator;
@property (nonatomic, strong) NSArray *tabTitles;
@property (nonatomic, strong) NSMutableArray *tabButtons;
@end

@implementation WBFPanelView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [WBFTheme bg0];
    self.layer.cornerRadius = 22;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    self.layer.borderWidth = 0.6;
    self.layer.borderColor = [[WBFTheme line] colorWithAlphaComponent:0.8].CGColor;
    self.tabTitles = @[@"任务", @"终端", @"工具", @"设置"];
    self.tabButtons = [NSMutableArray array];

    _header = [[UIView alloc] initWithFrame:CGRectZero];
    _header.backgroundColor = [WBFTheme bg1];
    [self addSubview:_header];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.text = @"WBF Agent";
    _titleLabel.font = [WBFTheme font:15 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [WBFTheme txt];
    [_header addSubview:_titleLabel];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusLabel.text = @"待命";
    _statusLabel.font = [WBFTheme font:10.5 weight:UIFontWeightRegular];
    _statusLabel.textColor = [WBFTheme sub];
    [_header addSubview:_statusLabel];

    NSArray *icons = @[@"xmark", @"plus.circle", @"clock.arrow.circlepath"];
    NSArray *sels = @[@"closeTapped", @"newTaskTapped", @"historyTapped"];
    CGFloat bx = 0;
    for (NSInteger i = 0; i < icons.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        UIImage *img = [UIImage systemImageNamed:icons[i]];
        [b setImage:img forState:UIControlStateNormal];
        b.tintColor = [WBFTheme sub];
        b.tag = i;
        SEL s = NSSelectorFromString(sels[i]);
        [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
        [_header addSubview:b];
        bx += 34;
    }

    _tabBar = [[UIView alloc] initWithFrame:CGRectZero];
    _tabBar.backgroundColor = [WBFTheme bg1];
    [self addSubview:_tabBar];

    _indicator = [[UIView alloc] initWithFrame:CGRectZero];
    _indicator.backgroundColor = [WBFTheme accent];
    _indicator.layer.cornerRadius = 1.5;
    [_tabBar addSubview:_indicator];

    for (NSInteger i = 0; i < self.tabTitles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        [b setTitle:self.tabTitles[i] forState:UIControlStateNormal];
        b.titleLabel.font = [WBFTheme font:12.5 weight:UIFontWeightMedium];
        [b setTitleColor:[WBFTheme sub] forState:UIControlStateNormal];
        b.tag = i;
        [b addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_tabBar addSubview:b];
        [self.tabButtons addObject:b];
    }

    _content = [[UIView alloc] initWithFrame:CGRectZero];
    _content.backgroundColor = [WBFTheme bg0];
    [self addSubview:_content];

    _taskView = [[WBFTaskView alloc] initWithFrame:_content.bounds];
    _terminalView = [[WBFTerminalView alloc] initWithFrame:_content.bounds];
    _toolsView = [[WBFToolsView alloc] initWithFrame:_content.bounds];
    _settingsView = [[WBFSettingsView alloc] initWithFrame:_content.bounds];
    for (UIView *v in @[_taskView, _terminalView, _toolsView, _settingsView]) {
        v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_content addSubview:v];
    }
    [self selectTab:0];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    _header.frame = CGRectMake(0, 0, w, 56);
    _titleLabel.frame = CGRectMake(18, 11, 200, 20);
    _statusLabel.frame = CGRectMake(18, 31, w - 160, 14);

    CGFloat bx = w - 12 - 34;
    for (NSInteger i = ((NSInteger)_header.subviews.count - 1); i >= 0; i--) {
        UIView *v = _header.subviews[(NSUInteger)i];
        if (![v isKindOfClass:[UIButton class]]) continue;
        v.frame = CGRectMake(bx, 12, 32, 32);
        bx -= 36;
    }

    _tabBar.frame = CGRectMake(0, 56, w, 40);
    CGFloat tw = w / (CGFloat)MAX((NSInteger)1, (NSInteger)self.tabButtons.count);
    for (NSInteger i = 0; i < (NSInteger)self.tabButtons.count; i++) {
        UIButton *b = self.tabButtons[(NSUInteger)i];
        b.frame = CGRectMake(tw * i, 0, tw, 38);
    }
    _indicator.frame = CGRectMake(tw * self.tab + tw * 0.28, 36, tw * 0.44, 3);

    _content.frame = CGRectMake(0, 96, w, MAX(0, h - 96));
    for (UIView *v in _content.subviews) v.frame = _content.bounds;

    UIView *line = [_tabBar viewWithTag:9911];
    if (!line) {
        line = [[UIView alloc] initWithFrame:CGRectZero];
        line.tag = 9911;
        line.backgroundColor = [[WBFTheme line] colorWithAlphaComponent:0.7];
        [_tabBar addSubview:line];
    }
    line.frame = CGRectMake(0, 39.5, w, 0.6);
    [_tabBar bringSubviewToFront:_indicator];
}

- (void)tabTapped:(UIButton *)sender {
    [self selectTab:sender.tag];
}

- (void)selectTab:(NSInteger)idx {
    self.tab = MAX(0, MIN(3, idx));
    NSArray *views = @[self.taskView ?: [UIView new], self.terminalView ?: [UIView new],
                       self.toolsView ?: [UIView new], self.settingsView ?: [UIView new]];
    for (NSInteger i = 0; i < (NSInteger)views.count; i++) {
        UIView *v = views[(NSUInteger)i];
        v.hidden = (i != self.tab);
    }
    for (NSInteger i = 0; i < (NSInteger)self.tabButtons.count; i++) {
        UIButton *b = self.tabButtons[(NSUInteger)i];
        BOOL on = (i == self.tab);
        [b setTitleColor:on ? [WBFTheme txt] : [WBFTheme sub] forState:UIControlStateNormal];
        b.titleLabel.font = [WBFTheme font:12.5 weight:on ? UIFontWeightSemibold : UIFontWeightMedium];
    }
    [self setNeedsLayout];
    if (self.tab == 1) [self.terminalView activateSession];
    if (self.tab == 3) [self.settingsView reload];
}

- (void)setStatus:(NSString *)text color:(UIColor *)color {
    self.statusLabel.text = text ?: @"";
    self.statusLabel.textColor = color ?: [WBFTheme sub];
}

- (void)appendToTask:(NSString *)text kind:(WBFBubbleKind)kind {
    [self.taskView appendText:text kind:kind];
}

- (void)reloadSettings {
    [self.settingsView reload];
}

- (void)closeTapped {
    if ([self.delegate respondsToSelector:@selector(panelDidRequestClose)]) {
        [self.delegate performSelector:@selector(panelDidRequestClose)];
    }
}

- (void)newTaskTapped {
    [self.taskView clearAll];
    [[WBFAgent shared] resetContext];
    [self selectTab:0];
    [self setStatus:@"新任务已就绪" color:[WBFTheme ok]];
}

- (void)historyTapped {
    NSArray *records = [[WBFConfig shared] history];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"任务记录"
                                                              message:records.count ? nil : @"暂无记录"
                                                       preferredStyle:UIAlertControllerStyleActionSheet];
    NSInteger n = 0;
    for (WBFTaskRecord *r in records) {
        if (n++ >= 12) break;
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"MM-dd HH:mm";
        NSString *title = [NSString stringWithFormat:@"%@ · %@", [df stringFromDate:r.date], [r displayTitle]];
        [ac addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self.taskView clearAll];
            [[WBFAgent shared] resetContext];
            [self.taskView appendText:[NSString stringWithFormat:@"载入记录：%@", r.task] kind:WBFBubbleInfo];
            for (NSDictionary *item in r.log) {
                NSString *role = item[@"role"] ?: @"";
                NSString *text = item[@"text"] ?: @"";
                if ([role isEqualToString:@"assistant"]) [self.taskView appendText:text kind:WBFBubbleAssistant];
                else if ([role isEqualToString:@"tool"]) [self.taskView appendText:text kind:WBFBubbleTool];
            }
            [self selectTab:0];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"清空全部记录" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[WBFConfig shared] clearHistory];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self wbf_present:ac];
}

- (void)wbf_present:(UIViewController *)vc {
    UIViewController *top = nil;
    UIWindow *w = self.window;
    if (w.rootViewController) top = w.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if (!top) {
        top = [[UIViewController alloc] init];
        top.view.backgroundColor = [UIColor clearColor];
        w.rootViewController = top;
    }
    [top presentViewController:vc animated:YES completion:nil];
}

@end

#pragma mark - Ball

@interface WBFBallView : UIView
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, strong) CAGradientLayer *grad;
@property (nonatomic, strong) UIView *ring;
@end

@implementation WBFBallView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.layer.cornerRadius = frame.size.width / 2.0;
    self.layer.masksToBounds = NO;

    _grad = [CAGradientLayer layer];
    _grad.colors = @[(id)[WBFTheme accent].CGColor, (id)[WBFTheme accent2].CGColor];
    _grad.startPoint = CGPointMake(0.1, 0.0);
    _grad.endPoint = CGPointMake(0.9, 1.0);
    _grad.frame = self.bounds;
    _grad.cornerRadius = frame.size.width / 2.0;
    [self.layer addSublayer:_grad];

    self.layer.shadowColor = [WBFTheme accent].CGColor;
    self.layer.shadowOpacity = 0.45;
    self.layer.shadowRadius = 12;
    self.layer.shadowOffset = CGSizeMake(0, 4);

    UILabel *icon = [[UILabel alloc] initWithFrame:self.bounds];
    icon.text = @"✦";
    icon.textAlignment = NSTextAlignmentCenter;
    icon.textColor = [UIColor whiteColor];
    icon.font = [WBFTheme font:24 weight:UIFontWeightSemibold];
    icon.userInteractionEnabled = NO;
    [self addSubview:icon];

    _ring = [[UIView alloc] initWithFrame:self.bounds];
    _ring.layer.cornerRadius = frame.size.width / 2.0;
    _ring.layer.borderWidth = 2.0;
    _ring.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.85].CGColor;
    _ring.alpha = 0.0;
    _ring.userInteractionEnabled = NO;
    [self addSubview:_ring];
    return self;
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    [_ring.layer removeAllAnimations];
    if (busy) {
        _ring.alpha = 0.9;
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        a.fromValue = @1.0;
        a.toValue = @1.55;
        a.duration = 1.1;
        a.repeatCount = HUGE_VAL;
        a.autoreverses = NO;
        [_ring.layer addAnimation:a forKey:@"pulse"];
        CABasicAnimation *o = [CABasicAnimation animationWithKeyPath:@"opacity"];
        o.fromValue = @0.85;
        o.toValue = @0.0;
        o.duration = 1.1;
        o.repeatCount = HUGE_VAL;
        [_ring.layer addAnimation:o forKey:@"fade"];
    } else {
        _ring.alpha = 0.0;
        _ring.transform = CGAffineTransformIdentity;
    }
}

@end

#pragma mark - Root

@interface WBFRoot () <WBFPanelDelegate>
@property (nonatomic, strong) UIWindow *ballWindow;
@property (nonatomic, strong) UIWindow *panelWindow;
@property (nonatomic, strong) UIWindow *dimWindow;
@property (nonatomic, strong) WBFBallView *ball;
@property (nonatomic, strong) WBFPanelView *panel;
@property (nonatomic, assign) BOOL installed;
@property (nonatomic, assign) BOOL panelOpen;
@property (nonatomic, assign) CGFloat kbHeight;
@property (nonatomic, assign) CGPoint ballPos;
@property (nonatomic, assign) NSInteger retries;
@end

@implementation WBFRoot

+ (instancetype)shared {
    static WBFRoot *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [WBFRoot new]; });
    return inst;
}

- (void)installWhenReady {
    if (self.installed) return;
    UIWindowScene *scene = WBFActiveScene();
    if (!scene) {
        if (self.retries++ > 120) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self installWhenReady];
        });
        return;
    }
    [self installIntoScene];
}

- (void)installIntoScene {
    if (self.installed) return;
    UIWindowScene *scene = WBFActiveScene();
    if (!scene) return;
    self.installed = YES;

    id saved = [[NSUserDefaults standardUserDefaults] objectForKey:@"wbf_ballpos"];
    if ([saved isKindOfClass:[NSString class]]) {
        NSArray *p = [(NSString *)saved componentsSeparatedByString:@","];
        if (p.count == 2) self.ballPos = CGPointMake([p[0] doubleValue], [p[1] doubleValue]);
        else self.ballPos = CGPointMake(0.93, 0.74);
    } else {
        self.ballPos = CGPointMake(0.93, 0.74);
    }

    self.ballWindow = [[UIWindow alloc] initWithWindowScene:scene];
    self.ballWindow.backgroundColor = [UIColor clearColor];
    self.ballWindow.windowLevel = UIWindowLevelAlert + 500;
    self.ballWindow.rootViewController = [[UIViewController alloc] init];
    self.ballWindow.rootViewController.view.backgroundColor = [UIColor clearColor];

    CGFloat bw = 58;
    self.ball = [[WBFBallView alloc] initWithFrame:CGRectMake(7, 7, bw, bw)];
    self.ball.userInteractionEnabled = YES;
    [self.ballWindow.rootViewController.view addSubview:self.ball];
    self.ball.alpha = [WBFConfig shared].ballOpacity;

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(ballPanned:)];
    [self.ball addGestureRecognizer:pan];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ballTapped)];
    [self.ball addGestureRecognizer:tap];

    self.ballWindow.hidden = NO;
    [self placeBall];

    self.dimWindow = [[UIWindow alloc] initWithWindowScene:scene];
    self.dimWindow.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
    self.dimWindow.windowLevel = UIWindowLevelAlert + 480;
    self.dimWindow.rootViewController = [[UIViewController alloc] init];
    self.dimWindow.rootViewController.view.backgroundColor = [UIColor clearColor];
    self.dimWindow.userInteractionEnabled = NO;
    self.dimWindow.hidden = YES;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
    [nc addObserver:self selector:@selector(orientationChanged) name:UIDeviceOrientationDidChangeNotification object:nil];

    __weak typeof(self) weakSelf = self;
    [WBFAgent shared].onEvent = ^(NSString *type, NSDictionary *info) {
        [weakSelf handleAgentEvent:type info:info];
    };
    [WBFShell shared].onOutput = ^(NSString *text) {
        WBFDispatchMain(^{ [weakSelf.panel.terminalView appendOutput:text]; });
    };

    // 预热工具探测（不阻塞启动）
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [WBFTouch hidAvailable];
        [[WBFShell shared] recheckDaemon];
    });

    NSLog(@"[WBF] installed into %@", [[NSBundle mainBundle] bundleIdentifier]);
}

- (void)placeBall {
    CGRect sb = [UIScreen mainScreen].bounds;
    CGFloat w = 72;
    CGFloat cx = self.ballPos.x * sb.size.width;
    CGFloat cy = self.ballPos.y * sb.size.height;
    cx = MAX(w / 2 + 2, MIN(sb.size.width - w / 2 - 2, cx));
    cy = MAX(w / 2 + 40, MIN(sb.size.height - w / 2 - 10, cy));
    self.ballWindow.frame = CGRectMake(cx - w / 2, cy - w / 2, w, w);
}

- (void)ballPanned:(UIPanGestureRecognizer *)g {
    UIWindow *win = self.ballWindow;
    CGPoint t = [g translationInView:win.superview ?: win];
    CGRect f = win.frame;
    f.origin.x += t.x;
    f.origin.y += t.y;
    win.frame = f;
    [g setTranslation:CGPointZero inView:win.superview ?: win];

    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        CGRect sb = [UIScreen mainScreen].bounds;
        CGPoint c = CGPointMake(CGRectGetMidX(win.frame), CGRectGetMidY(win.frame));
        CGFloat nx = (c.x < sb.size.width / 2) ? 0.07 : 0.93;
        CGFloat ny = MAX(0.08, MIN(0.94, c.y / sb.size.height));
        self.ballPos = CGPointMake(nx, ny);
        [[NSUserDefaults standardUserDefaults] setObject:[NSString stringWithFormat:@"%.3f,%.3f", nx, ny]
                                                  forKey:@"wbf_ballpos"];
        [UIView animateWithDuration:0.22 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.6
                            options:UIViewAnimationOptionCurveEaseOut animations:^{
            [self placeBall];
        } completion:nil];
    }
}

- (void)ballTapped {
    if (self.panelOpen) [self hidePanel];
    else [self showPanel];
}

- (CGRect)cardFrame {
    CGRect sb = [UIScreen mainScreen].bounds;
    UIEdgeInsets ins = UIEdgeInsetsMake(24, 0, 24, 0);
    UIWindow *host = WBFHostWindow();
    if (host) ins = host.safeAreaInsets;
    CGFloat w = MIN(sb.size.width - 18, 470);
    CGFloat top = ins.top + 34;
    CGFloat bottomInset = self.kbHeight > 1 ? (self.kbHeight + 10) : (ins.bottom + 26);
    CGFloat bottom = sb.size.height - bottomInset;
    CGFloat h = MAX(300, bottom - top);
    return CGRectMake((sb.size.width - w) / 2.0, top, w, h);
}

- (void)showPanel {
    if (!self.installed) [self installWhenReady];
    if (!self.panelWindow) {
        UIWindowScene *scene = WBFActiveScene();
        if (!scene) return;
        self.panelWindow = [[UIWindow alloc] initWithWindowScene:scene];
        self.panelWindow.backgroundColor = [UIColor clearColor];
        self.panelWindow.windowLevel = UIWindowLevelAlert + 520;
        UIViewController *vc = [[UIViewController alloc] init];
        vc.view.backgroundColor = [UIColor clearColor];
        self.panelWindow.rootViewController = vc;

        self.panel = [[WBFPanelView alloc] initWithFrame:vc.view.bounds];
        self.panel.delegate = self;
        self.panel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [vc.view addSubview:self.panel];
    }
    CGRect cf = [self cardFrame];
    self.panelWindow.frame = cf;
    self.panelWindow.hidden = NO;
    self.panel.frame = self.panelWindow.rootViewController.view.bounds;
    self.panel.alpha = 0.0;
    self.panel.transform = CGAffineTransformMakeScale(0.94, 0.94);

    self.dimWindow.frame = [UIScreen mainScreen].bounds;
    self.dimWindow.hidden = NO;
    self.dimWindow.alpha = 0.0;

    [UIView animateWithDuration:0.26 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.panel.alpha = 1.0;
        self.panel.transform = CGAffineTransformIdentity;
        self.dimWindow.alpha = 1.0;
        self.ball.alpha = 0.0;
    } completion:^(BOOL done) {
        self.panelOpen = YES;
        [self.panel selectTab:self.panel.tab];
        if (self.panel.tab == 0) [self.panel.taskView reloadHistory];
    }];
    [self refreshStatus];
}

- (void)hidePanel {
    [self.panelWindow endEditing:YES];
    [UIView animateWithDuration:0.2 animations:^{
        self.panel.alpha = 0.0;
        self.panel.transform = CGAffineTransformMakeScale(0.95, 0.95);
        self.dimWindow.alpha = 0.0;
        self.ball.alpha = [WBFConfig shared].ballOpacity;
    } completion:^(BOOL done) {
        self.panelWindow.hidden = YES;
        self.dimWindow.hidden = YES;
        self.panelOpen = NO;
    }];
}

- (BOOL)panelVisible { return self.panelOpen; }

- (void)panelDidRequestClose { [self hidePanel]; }

- (void)refreshStatus {
    WBFAgent *agent = [WBFAgent shared];
    if (!self.panel) return;
    if (agent.running) {
        [self.panel setStatus:[NSString stringWithFormat:@"运行中 · 第 %ld 步", (long)agent.step]
                        color:[WBFTheme ok]];
    } else {
        [self.panel setStatus:[NSString stringWithFormat:@"待命 · %@", [[WBFShell shared] engineName]]
                        color:[WBFTheme sub]];
    }
}

- (void)handleAgentEvent:(NSString *)type info:(NSDictionary *)info {
    WBFTaskView *tv = self.panel.taskView;
    [tv handleEvent:type info:info];
    [self.ball setBusy:[WBFAgent shared].running];

    if ([type isEqualToString:@"tokens"]) {
        [tv updateContextUsed:[info[@"used"] integerValue]
                        limit:[info[@"limit"] integerValue]
                         step:[info[@"step"] integerValue]];
    } else if ([type isEqualToString:@"thinking"]) {
        BOOL on = [info[@"on"] boolValue];
        [self.panel setStatus:on ? @"思考中…" : @"执行中…" color:[WBFTheme accent]];
    } else if ([type isEqualToString:@"done"]) {
        [self refreshStatus];
        [tv setBusy:NO];
    } else if ([type isEqualToString:@"error"]) {
        [self.panel setStatus:@"出错" color:[WBFTheme danger]];
    }
    if (![WBFAgent shared].running) [tv setBusy:NO];
}

- (void)keyboardChanged:(NSNotification *)note {
    NSDictionary *ui = note.userInfo;
    CGRect end = [ui[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    double dur = [ui[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    CGRect sb = [UIScreen mainScreen].bounds;
    CGFloat kb = 0;
    if (note.name != UIKeyboardWillHideNotification && end.size.height > 1) {
        kb = MAX(0, sb.size.height - end.origin.y);
    }
    self.kbHeight = kb;
    if (!self.panelOpen) return;
    [UIView animateWithDuration:(dur > 0 ? dur : 0.25) delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.panelWindow.frame = [self cardFrame];
        self.panel.frame = self.panelWindow.rootViewController.view.bounds;
        [self.panel setNeedsLayout];
        [self.panel layoutIfNeeded];
    } completion:nil];
}

- (void)orientationChanged {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self placeBall];
        self.dimWindow.frame = [UIScreen mainScreen].bounds;
        if (self.panelOpen) {
            self.panelWindow.frame = [self cardFrame];
            self.panel.frame = self.panelWindow.rootViewController.view.bounds;
        }
    });
}

@end
