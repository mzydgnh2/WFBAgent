//
//  WBFTouch.m
//

#import "WBFTouch.h"
#import <dlfcn.h>
#import <mach/mach_time.h>

typedef void *WBFIOHIDEventRef;
typedef double WBFIOHIDFloat;

typedef WBFIOHIDEventRef (*WBFDigitizerFn)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
                                           uint32_t, uint32_t, WBFIOHIDFloat, WBFIOHIDFloat, WBFIOHIDFloat,
                                           WBFIOHIDFloat, WBFIOHIDFloat, Boolean, Boolean, uint32_t);
typedef WBFIOHIDEventRef (*WBFFingerFn)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
                                       WBFIOHIDFloat, WBFIOHIDFloat, WBFIOHIDFloat, WBFIOHIDFloat,
                                       WBFIOHIDFloat, Boolean, Boolean, uint32_t);
typedef void (*WBFAppendFn)(WBFIOHIDEventRef, WBFIOHIDEventRef, uint32_t);
typedef void (*WBFSetIntFn)(WBFIOHIDEventRef, uint32_t, long long);

static WBFDigitizerFn gDigitizer = NULL;
static WBFFingerFn    gFinger    = NULL;
static WBFAppendFn    gAppend    = NULL;
static WBFSetIntFn    gSetInt    = NULL;
static BOOL           gLoaded    = NO;
static BOOL           gUsable    = NO;

// IOHIDDigitizerTransducerType / event masks (IOHIDEventTypes.h)
static const uint32_t kTransducerHand   = 3;
static const uint32_t kTransducerFinger = 2;
static const uint32_t kEvRange    = 0x00000001;
static const uint32_t kEvTouch    = 0x00000002;
static const uint32_t kEvPosition = 0x00000004;
static const uint32_t kEvStart    = 0x00000100;
static const uint32_t kFieldIsBuiltIn = 0x000A0000;

@implementation WBFTouch

+ (void)load {
    if (gLoaded) return;
    gLoaded = YES;
    void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!h) h = dlopen("/System/Library/PrivateFrameworks/IOKit.framework/IOKit", RTLD_LAZY);
    gDigitizer = (WBFDigitizerFn)dlsym(RTLD_DEFAULT, "IOHIDEventCreateDigitizerEvent");
    gFinger    = (WBFFingerFn)dlsym(RTLD_DEFAULT, "IOHIDEventCreateDigitizerFingerEvent");
    gAppend    = (WBFAppendFn)dlsym(RTLD_DEFAULT, "IOHIDEventAppendEvent");
    gSetInt    = (WBFSetIntFn)dlsym(RTLD_DEFAULT, "IOHIDEventSetIntegerValue");
    if (!gDigitizer && h) gDigitizer = (WBFDigitizerFn)dlsym(h, "IOHIDEventCreateDigitizerEvent");
    if (!gFinger && h)    gFinger    = (WBFFingerFn)dlsym(h, "IOHIDEventCreateDigitizerFingerEvent");
    if (!gAppend && h)    gAppend    = (WBFAppendFn)dlsym(h, "IOHIDEventAppendEvent");
    if (!gSetInt && h)    gSetInt    = (WBFSetIntFn)dlsym(h, "IOHIDEventSetIntegerValue");
    gUsable = (gDigitizer && gFinger && gAppend &&
               [[UIApplication sharedApplication] respondsToSelector:NSSelectorFromString(@"_enqueueHIDEvent:")]);
    NSLog(@"[WBF] HID engine: %@", gUsable ? @"IOHIDEvent" : @"UIKit-fallback");
}

+ (BOOL)hidAvailable {
    if (!gLoaded) [self load];
    return gUsable;
}

+ (NSString *)engineName {
    return [self hidAvailable] ? @"IOHIDEvent (真实触摸注入)" : @"UIKit 降级 (控件激活)";
}

#pragma mark - raw events

static void WBFEmit(CGPoint p, uint32_t mask, Boolean touch, Boolean range) {
    if (!gUsable) return;
    uint64_t now = mach_absolute_time();
    WBFIOHIDEventRef hand = gDigitizer(kCFAllocatorDefault, now, kTransducerHand, 0, 0, 0, 0,
                                       0, 0, 0, 0, 0, 0, 0, 0);
    if (!hand) return;
    WBFIOHIDEventRef finger = gFinger(kCFAllocatorDefault, now, 1, 1, mask,
                                      p.x, p.y, 0, 0, 0, range, touch, 0);
    if (finger) {
        gAppend(hand, finger, 0);
        if (gSetInt) gSetInt(hand, kFieldIsBuiltIn, 1);
        CFRelease((CFTypeRef)finger);
    }
    UIApplication *app = [UIApplication sharedApplication];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    if ([app respondsToSelector:NSSelectorFromString(@"_enqueueHIDEvent:")]) {
        [app performSelector:NSSelectorFromString(@"_enqueueHIDEvent:") withObject:(__bridge id)hand];
    }
#pragma clang diagnostic pop
    CFRelease((CFTypeRef)hand);
}

+ (void)touchDown:(CGPoint)p {
    if (![self hidAvailable]) return;
    WBFEmit(p, kEvPosition | kEvTouch | kEvRange | kEvStart, 1, 1);
}

+ (void)touchMove:(CGPoint)p {
    if (![self hidAvailable]) return;
    WBFEmit(p, kEvPosition | kEvTouch | kEvRange, 1, 1);
}

+ (void)touchUp:(CGPoint)p {
    if (![self hidAvailable]) return;
    WBFEmit(p, kEvPosition | kEvTouch | kEvRange, 0, 1);
}

#pragma mark - fallback

static void WBFFallbackTap(CGPoint p) {
    UIWindow *w = WBFHostWindow();
    if (!w) return;
    UIView *hit = [w hitTest:p withEvent:nil];
    UIView *v = hit;
    while (v) {
        if ([v isKindOfClass:[UIControl class]]) {
            UIControl *c = (UIControl *)v;
            [c sendActionsForControlEvents:UIControlEventTouchDown];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.03 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [c sendActionsForControlEvents:UIControlEventTouchUpInside];
            });
            return;
        }
        if ([v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]]) {
            NSIndexPath *ip = [(UITableView *)v indexPathForRowAtPoint:[v convertPoint:p fromView:w]];
            if (ip && [v isKindOfClass:[UITableView class]]) {
                id del = [(UITableView *)v delegate];
                if ([del respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
                    [del tableView:(UITableView *)v didSelectRowAtIndexPath:ip];
                    return;
                }
            }
        }
        v = v.superview;
    }
    if (hit) {
        if ([hit respondsToSelector:@selector(accessibilityActivate)]) {
            if ([hit accessibilityActivate]) return;
        }
        id target = [hit nextResponder];
        if ([target respondsToSelector:NSSelectorFromString(@"accessibilityActivate")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [target performSelector:NSSelectorFromString(@"accessibilityActivate")];
#pragma clang diagnostic pop
            return;
        }
    }
    NSLog(@"[WBF] fallback tap missed at %@", NSStringFromCGPoint(p));
}

#pragma mark - public

+ (void)tap:(CGPoint)p {
    if ([self hidAvailable]) {
        [self touchDown:p];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.045 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self touchUp:p];
        });
    } else {
        WBFFallbackTap(p);
    }
}

+ (void)longPress:(CGPoint)p duration:(double)d {
    if (![self hidAvailable]) { WBFFallbackTap(p); return; }
    [self touchDown:p];
    double hold = MAX(0.5, d);
    NSInteger steps = MAX(3, (NSInteger)(hold / 0.15));
    for (NSInteger i = 1; i <= steps; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((hold * i / steps) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (i == steps) [self touchUp:p];
            else [self touchMove:p];
        });
    }
}

+ (void)swipeFrom:(CGPoint)a to:(CGPoint)b duration:(double)d {
    if (![self hidAvailable]) {
        NSLog(@"[WBF] swipe needs HID engine");
        return;
    }
    double dur = MAX(0.08, d);
    NSInteger steps = MAX(8, (NSInteger)(dur * 60));
    [self touchDown:a];
    for (NSInteger i = 1; i <= steps; i++) {
        double t = (double)i / (double)steps;
        CGPoint p = CGPointMake(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
        int64_t delay = (int64_t)(dur * t * NSEC_PER_SEC);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay), dispatch_get_main_queue(), ^{
            if (i == steps) [self touchUp:p];
            else [self touchMove:p];
        });
    }
}

+ (UIView *)firstResponderIn:(UIView *)v {
    if (v.isFirstResponder) return v;
    for (UIView *s in v.subviews) {
        UIView *r = [self firstResponderIn:s];
        if (r) return r;
    }
    return nil;
}

+ (UIView *)firstResponder {
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass(w.class) hasPrefix:@"WBF"]) continue;
        UIView *r = [self firstResponderIn:w];
        if (r) return r;
    }
    return nil;
}

+ (BOOL)typeText:(NSString *)text {
    if (!text.length) return YES;
    UIView *fr = [self firstResponder];
    if ([fr respondsToSelector:@selector(insertText:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [fr performSelector:@selector(insertText:) withObject:text];
#pragma clang diagnostic pop
        return YES;
    }
    // try UITextInput protocol on any responder in the chain
    id r = fr;
    while (r) {
        if ([r conformsToProtocol:@protocol(UIKeyInput)]) {
            [(id<UIKeyInput>)r insertText:text];
            return YES;
        }
        r = [r nextResponder];
    }
    // last resort: find a visible text field and set its text
    UIWindow *w = WBFHostWindow();
    UITextField *tf = [self findTextField:w];
    if (tf) {
        tf.text = [tf.text ?: @"" stringByAppendingString:text];
        [tf sendActionsForControlEvents:UIControlEventEditingChanged];
        return YES;
    }
    return NO;
}

+ (UITextField *)findTextField:(UIView *)v {
    if ([v isKindOfClass:[UITextField class]] && !v.hidden && v.alpha > 0.05) return (UITextField *)v;
    for (UIView *s in v.subviews) {
        UITextField *r = [self findTextField:s];
        if (r) return r;
    }
    return nil;
}

+ (BOOL)pressKey:(NSString *)key {
    UIView *fr = [self firstResponder];
    NSString *k = [key lowercaseString];
    if ([k isEqualToString:@"delete"] || [k isEqualToString:@"backspace"]) {
        if ([fr respondsToSelector:@selector(deleteBackward)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [fr performSelector:@selector(deleteBackward)];
#pragma clang diagnostic pop
            return YES;
        }
        UITextField *tf = fr && [fr isKindOfClass:[UITextField class]] ? (UITextField *)fr : [self findTextField:WBFHostWindow()];
        if (tf.text.length) {
            tf.text = [tf.text substringToIndex:tf.text.length - 1];
            [tf sendActionsForControlEvents:UIControlEventEditingChanged];
            return YES;
        }
        return NO;
    }
    if ([k isEqualToString:@"return"] || [k isEqualToString:@"enter"]) {
        if ([fr isKindOfClass:[UITextField class]]) {
            [(UITextField *)fr sendActionsForControlEvents:UIControlEventEditingDidEndOnExit];
            return YES;
        }
        if ([fr respondsToSelector:@selector(insertText:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [fr performSelector:@selector(insertText:) withObject:@"\n"];
#pragma clang diagnostic pop
            return YES;
        }
        return NO;
    }
    [self typeText:key];
    return YES;
}

+ (void)resignKeyboard {
    [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
    UIView *fr = [self firstResponder];
    [fr resignFirstResponder];
}

@end
