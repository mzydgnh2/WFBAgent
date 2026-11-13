//
//  WBFTouch.h
//  Real touch injection (IOHIDEvent) + UIKit fallbacks
//

#pragma once
#import "WBFCompat.h"

@interface WBFTouch : NSObject
+ (BOOL)hidAvailable;
+ (NSString *)engineName;

+ (void)tap:(CGPoint)p;
+ (void)longPress:(CGPoint)p duration:(double)d;
+ (void)swipeFrom:(CGPoint)a to:(CGPoint)b duration:(double)d;
+ (void)touchDown:(CGPoint)p;
+ (void)touchMove:(CGPoint)p;
+ (void)touchUp:(CGPoint)p;

+ (BOOL)typeText:(NSString *)text;
+ (BOOL)pressKey:(NSString *)key;
+ (UIView *)firstResponder;
+ (void)resignKeyboard;
@end
