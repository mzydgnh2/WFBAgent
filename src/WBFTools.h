//
//  WBFTools.h
//  Real on-device tool implementations exposed to the model
//

#pragma once
#import "WBFCompat.h"

extern NSString *const WBFToolFinishMarker;

@interface WBFTools : NSObject
+ (instancetype)shared;
@property (nonatomic, strong) NSMutableArray *pendingImages;   // base64 jpeg
@property (nonatomic, strong) NSMutableArray *elements;        // NSValue(nonretained) of indexed views

- (NSArray *)schemas;
- (NSString *)execute:(NSString *)name arguments:(NSDictionary *)args;

- (UIImage *)snapshot;
- (NSString *)dumpUITree:(NSInteger)maxDepth;
@end
