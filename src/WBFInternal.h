//
//  WBFInternal.h
//  Shared declarations between the panel shell and the tab views
//

#pragma once
#import "WBFCompat.h"
#import "WBFConfig.h"

@interface WBFTheme : NSObject
+ (UIColor *)bg0;
+ (UIColor *)bg1;
+ (UIColor *)bg2;
+ (UIColor *)bg3;
+ (UIColor *)line;
+ (UIColor *)txt;
+ (UIColor *)sub;
+ (UIColor *)accent;
+ (UIColor *)accent2;
+ (UIColor *)ok;
+ (UIColor *)warn;
+ (UIColor *)danger;
+ (UIFont *)font:(CGFloat)size weight:(UIFontWeight)weight;
+ (UIFont *)mono:(CGFloat)size;
@end

typedef NS_ENUM(NSInteger, WBFBubbleKind) {
    WBFBubbleUser = 0,
    WBFBubbleAssistant,
    WBFBubbleTool,
    WBFBubbleError,
    WBFBubbleInfo
};

@interface WBFBubble : UIView
- (instancetype)initWithText:(NSString *)text kind:(WBFBubbleKind)kind maxWidth:(CGFloat)maxW;
@property (nonatomic, assign) CGFloat bubbleHeight;
- (CGFloat)placeAtY:(CGFloat)y width:(CGFloat)w;
@end

@class WBFTaskView, WBFTerminalView, WBFToolsView, WBFSettingsView;

@interface WBFTaskView : UIView
- (void)appendText:(NSString *)text kind:(WBFBubbleKind)kind;
- (void)clearAll;
- (void)handleEvent:(NSString *)type info:(NSDictionary *)info;
- (void)updateContextUsed:(NSInteger)used limit:(NSInteger)limit step:(NSInteger)step;
- (void)setBusy:(BOOL)busy;
- (BOOL)isBusy;
- (void)reloadHistory;
@end

@interface WBFTerminalView : UIView
- (void)appendOutput:(NSString *)text;
- (void)activateSession;
@end

@interface WBFToolsView : UIView
- (void)runToolNamed:(NSString *)name args:(NSDictionary *)args;
@end

@interface WBFSettingsView : UIView
- (void)reload;
@end

@interface WBFPanelView : UIView
@property (nonatomic, weak) id delegate;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) WBFTaskView *taskView;
@property (nonatomic, strong) WBFTerminalView *terminalView;
@property (nonatomic, strong) WBFToolsView *toolsView;
@property (nonatomic, strong) WBFSettingsView *settingsView;
@property (nonatomic, assign) NSInteger tab;
- (void)selectTab:(NSInteger)idx;
- (void)setStatus:(NSString *)text color:(UIColor *)color;
- (void)appendToTask:(NSString *)text kind:(WBFBubbleKind)kind;
- (void)reloadSettings;
@end
