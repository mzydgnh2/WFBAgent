//
//  WBFCompat.h
//  WFBAgent - in-process AI agent for jailbroken iOS
//

#pragma once
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

static inline void WBFDispatchMain(void (^block)(void)) {
    if (!block) return;
    if ([NSThread isMainThread]) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

static inline NSString *WBFTrim(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return @"";
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static inline NSString *WBFFmt(double v) {
    return [NSString stringWithFormat:@"%.1f", v];
}

static inline UIWindow *WBFKeyWindow(void) {
    UIWindow *res = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            if (s.activationState != UISceneActivationStateForegroundActive) continue;
            UIWindowScene *ws = (UIWindowScene *)s;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) { res = w; break; }
            }
            if (!res) {
                for (UIWindow *w in ws.windows) {
                    if (!w.hidden && w.alpha > 0.01) { res = w; break; }
                }
            }
            if (res) break;
        }
    }
    if (!res) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        res = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
    }
    if (!res) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (!w.hidden && ![NSStringFromClass(w.class) hasPrefix:@"WBF"]) { res = w; break; }
        }
    }
    return res;
}

// The first window that belongs to the host app (never our overlay windows).
static inline UIWindow *WBFHostWindow(void) {
    UIWindow *w = WBFKeyWindow();
    if (w && [NSStringFromClass(w.class) hasPrefix:@"WBF"]) {
        for (UIWindow *c in [UIApplication sharedApplication].windows) {
            if (![NSStringFromClass(c.class) hasPrefix:@"WBF"] && !c.hidden) return c;
        }
    }
    return w;
}

static inline UIWindowScene *WBFActiveScene(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] &&
                s.activationState == UISceneActivationStateForegroundActive) {
                return (UIWindowScene *)s;
            }
            if ([s isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)s).windows) {
                    if (![NSStringFromClass(w.class) hasPrefix:@"WBF"]) return (UIWindowScene *)s;
                }
            }
        }
    }
    return nil;
}

@interface UIApplication (WBFHID)
- (void)_enqueueHIDEvent:(id)event;
@end

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
- (BOOL)openSensitiveURL:(NSURL *)url withOptions:(id)options;
- (NSArray *)allInstalledApplications;
@end

@interface LSApplicationProxy : NSObject
- (NSString *)applicationIdentifier;
- (NSString *)localizedName;
- (NSString *)bundleIdentifier;
- (NSURL *)bundleURL;
@end
