//
//  GJGCChatInputExpandMenuPanelDataSource.h
//  Connect
//
//  Created by KivenLin on 14-10-28.
//  Copyright (c) 2014年 ConnectSoft. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GJGCChatInputConst.h"
#import "GJGCChatInputExpandMenuPanelConfigModel.h"

#define GJGCChatInputExpandMenuPanelDataSourceTitleKey @"GJGCChatInputExpandMenuPanelDataSourceTitleKey"

#define GJGCChatInputExpandMenuPanelDataSourceIconNormalKey @"GJGCChatInputExpandMenuPanelDataSourceIconNormalKey"

#define GJGCChatInputExpandMenuPanelDataSourceIconHighlightKey @"GJGCChatInputExpandMenuPanelDataSourceIconHighlightKey"

#define GJGCChatInputExpandMenuPanelDataSourceActionTypeKey @"GJGCChatInputExpandMenuPanelDataSourceActionTypeKey"

@interface GJGCChatInputExpandMenuPanelDataSource : NSObject

+ (NSArray *)menuItemDataSourceWithConfigModel:(GJGCChatInputExpandMenuPanelConfigModel *)configModel;

@end
