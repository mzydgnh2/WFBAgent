//
//  WBFAgent.h
//

#pragma once
#import "WBFConfig.h"

@interface WBFAgent : NSObject
+ (instancetype)shared;

@property (nonatomic, strong) NSMutableArray<WBFMsg *> *messages;
@property (nonatomic, strong) WBFTaskRecord *record;
@property (nonatomic, assign) NSInteger usedTokens;
@property (nonatomic, assign) NSInteger step;
@property (nonatomic, readonly) BOOL running;

// event types: user / assistant / tool / thinking / tokens / done / error / truncated
@property (nonatomic, copy) void (^onEvent)(NSString *type, NSDictionary *info);

- (void)startTask:(NSString *)task;
- (void)stop;
- (void)resetContext;
- (NSInteger)contextPercent;
@end
