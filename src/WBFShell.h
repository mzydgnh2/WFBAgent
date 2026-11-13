//
//  WBFShell.h
//  Real command execution: root helper daemon -> posix_spawn -> builtin fallback
//

#pragma once
#import "WBFCompat.h"

@interface WBFShell : NSObject
+ (instancetype)shared;

@property (nonatomic, copy) void (^onOutput)(NSString *text);

- (BOOL)daemonAvailable;        // cached
- (BOOL)recheckDaemon;
- (NSString *)engineName;

- (NSString *)exec:(NSString *)command timeout:(double)timeout;

- (BOOL)sessionOpen;
- (BOOL)openSession;
- (void)sendInput:(NSString *)input;
- (void)closeSession;
@end
