//
//  WBFUI.h
//

#pragma once
#import "WBFCompat.h"

@interface WBFRoot : NSObject
+ (instancetype)shared;
- (void)installWhenReady;
- (void)showPanel;
- (void)hidePanel;
- (BOOL)panelVisible;
- (void)installIntoScene;
@end
