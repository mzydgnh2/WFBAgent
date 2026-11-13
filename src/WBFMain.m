//
//  WBFMain.m
//  Entry point: the dylib installs the agent UI into the host app.
//

#import "WBFUI.h"
#import "WBFConfig.h"

static void WBFBootstrap(void) {
    static BOOL started = NO;
    if (started) return;
    started = YES;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:UIApplicationDidFinishLaunchingNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        [[WBFRoot shared] installWhenReady];
    }];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        if (![[WBFRoot shared] panelVisible]) [[WBFRoot shared] installWhenReady];
    }];

    // 兜底：若启动通知已错过（dylib 注入时机较晚），延时后直接安装
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[WBFRoot shared] installWhenReady];
    });
}

__attribute__((constructor)) static void WBFEntry(void) {
    @autoreleasepool {
        // 主线程可用时立刻挂载，否则等下一个 runloop
        dispatch_async(dispatch_get_main_queue(), ^{
            WBFBootstrap();
        });
    }
}
