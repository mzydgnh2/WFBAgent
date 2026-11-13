//
//  WBFConfig.h
//

#pragma once
#import "WBFCompat.h"

@interface WBFMsg : NSObject
@property (nonatomic, copy) NSString *role;        // system | user | assistant | tool
@property (nonatomic, copy) NSString *content;
@property (nonatomic, strong) NSArray *toolCalls;  // [{id,name,args}]
@property (nonatomic, copy) NSString *toolCallId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSArray *images;     // base64 jpeg (no prefix)
+ (instancetype)role:(NSString *)role content:(NSString *)content;
- (NSDictionary *)apiDict;
- (NSDictionary *)logDict;
+ (instancetype)fromLogDict:(NSDictionary *)d;
@end

@interface WBFTaskRecord : NSObject
@property (nonatomic, copy) NSString *taskId;
@property (nonatomic, copy) NSString *task;
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, strong) NSMutableArray *log;   // [{role,text,kind}]
@property (nonatomic, assign) NSInteger tokens;
@property (nonatomic, assign) NSInteger steps;
@property (nonatomic, copy) NSString *status;        // done | stopped | failed | running
+ (instancetype)newTask:(NSString *)task;
- (NSDictionary *)dict;
+ (instancetype)fromDict:(NSDictionary *)d;
- (NSString *)displayTitle;
@end

@interface WBFConfig : NSObject

@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, strong) NSArray *modelList;
@property (nonatomic, assign) NSInteger maxContext;      // tokens
@property (nonatomic, assign) double temperature;
@property (nonatomic, assign) NSInteger maxSteps;
@property (nonatomic, assign) NSInteger maxTokens;       // per reply, 0 = auto
@property (nonatomic, assign) BOOL sendScreenshot;       // attach screenshot every step
@property (nonatomic, assign) NSInteger inputMode;        // 0 text / 1 text+shot / 2 text+ui tree
@property (nonatomic, assign) BOOL confirmDanger;        // ask before destructive shell cmds
@property (nonatomic, assign) double ballOpacity;
@property (nonatomic, assign) BOOL ballAutostart;
@property (nonatomic, copy) NSString *language;          // zh | en
@property (nonatomic, assign) BOOL terminalFallbackEcho; // echo input in terminal

+ (instancetype)shared;
- (void)save;

- (NSArray<WBFTaskRecord *> *)history;
- (void)saveHistory;
- (void)addRecord:(WBFTaskRecord *)rec;
- (void)removeRecord:(NSString *)taskId;
- (void)clearHistory;
@end
