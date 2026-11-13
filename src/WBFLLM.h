//
//  WBFLLM.h
//

#pragma once
#import "WBFConfig.h"

typedef void (^WBFLLMCompletion)(NSDictionary *message, NSDictionary *usage, NSError *error);
typedef void (^WBFModelsCompletion)(NSArray<NSString *> *models, NSError *error);

NSInteger WBFEstimateTokens(NSString *text);
NSInteger WBFEstimateMessages(NSArray<WBFMsg *> *messages);

@interface WBFLLM : NSObject
+ (instancetype)shared;
- (void)chat:(NSArray<WBFMsg *> *)messages tools:(NSArray *)tools completion:(WBFLLMCompletion)done;
- (void)fetchModels:(WBFModelsCompletion)done;
- (void)probe:(void (^)(NSString *summary))done;
@property (nonatomic, assign) NSInteger lastTotalTokens;
@end
