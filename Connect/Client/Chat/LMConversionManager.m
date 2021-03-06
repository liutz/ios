//
//  LMConversionManager.m
//  Connect
//
//  Created by MoHuilin on 2017/1/18.
//  Copyright © 2017年 Connect. All rights reserved.
//

#import "LMConversionManager.h"
#import "RecentChatDBManager.h"
#import "MessageDBManager.h"
#import "GroupDBManager.h"
#import "UserDBManager.h"
#import "NSMutableArray+MoveObject.h"
#import "CIImageCacheManager.h"
#import "IMService.h"
#import "ConnectTool.h"

@interface LMConversionManager ()

@property (assign ,nonatomic)BOOL syncContacting;
@property (strong ,nonatomic)NSMutableDictionary *unNotiMessageCountDict;
@property (strong ,nonatomic)NSMutableArray *noFriendShipPulickArray;

@end

@implementation LMConversionManager

CREATE_SHARED_MANAGER(LMConversionManager)

- (instancetype)init{
    if (self = [super init]) {
        
        self.unNotiMessageCountDict = [NSMutableDictionary dictionary];
        self.noFriendShipPulickArray = [NSMutableArray array];
        
        RegisterNotify(ConnectGetOfflieCompleteNotification, @selector(getOfflineComplete));
        RegisterNotify(ConnectDownAllNewGroupAvatarNotification, @selector(groupAvatarChange));
        RegisterNotify(ConnectUpdateMyNickNameNotification, @selector(groupNicknameChange));
        RegisterNotify(SendDraftChangeNotification, @selector(haveDraft:));
        RegisterNotify(SessionManagerClearReadCountNoti, @selector(clearUnReadCount:));
        RegisterNotify(TopChatStatusChangeNotication, @selector(topChatStatusChange:));
        RegisterNotify(ConnnectRecentChatDeleteNotification, @selector(deleteRecentChat:));
        RegisterNotify(ConnnectSendMessageSuccessNotification, @selector(sendMessageSuccess:));
        RegisterNotify(ConnnectRecentChatChangeNotification, @selector(recentChatChange:));
        RegisterNotify(ConnnectNewChatChangeNotification, @selector(recentChatChange:));
        RegisterNotify(ConnnectContactDidChangeNotification, @selector(ContactInfoChange:));
        RegisterNotify(ConnnectGroupInfoDidChangeNotification, @selector(GroupInfoChange:));
        RegisterNotify(ConnnectQuitGroupNotification, @selector(quitGroup:));

        RegisterNotify(kAcceptNewFriendRequestNotification, @selector(acceptRequest:));
        RegisterNotify(ConnnectContactDidChangeDeleteUserNotification, @selector(deleteUser:));
        RegisterNotify(kFriendListChangeNotification,@selector(friendListChange:));
        RegisterNotify(ConnnectMuteNotification, @selector(muteChange:));
    }
    return self;
}

- (void)clearAllModel{
    [[SessionManager sharedManager] clearAllModel];
    [self.unNotiMessageCountDict removeAllObjects];
    [self.noFriendShipPulickArray removeAllObjects];
}

- (void)getAllConversationFromDB{
    
    [[RecentChatDBManager sharedManager] getAllRecentChatWithComplete:^(NSArray *allRecentChats) {
        [GCDQueue executeInMainQueue:^{
            [SessionManager sharedManager].allRecentChats = [NSMutableArray arrayWithArray:allRecentChats];
            [SessionManager sharedManager].topChatCount = 0;
            for (RecentChatModel *model in allRecentChats) {
                if (model.isTopChat) {
                    [SessionManager sharedManager].topChatCount ++;
                }
            }
            if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
            }
            
            if ([self.conversationListDelegate respondsToSelector:@selector(unreadMessageNumberDidChanged)]) {
                [self.conversationListDelegate unreadMessageNumberDidChanged];
            }

        }];
    }];
}

- (void)getNewMessagesWithLastMessage:(ChatMessageInfo *)lastMessage newMessageCount:(int)messageCount type:(GJGCChatFriendTalkType)type withSnapChatTime:(long long)snapChatTime{
    
    RecentChatModel *recentModel = nil;
    
    switch (type) {
        case GJGCChatFriendTalkTypePrivate:
        {
            recentModel = [[SessionManager sharedManager] getRecentChatWithIdentifier:lastMessage.messageOwer];
            if (!recentModel) {
                AccountInfo *contact = [[UserDBManager sharedManager] getUserByPublickey:lastMessage.messageOwer];
                if (!contact &&
                    lastMessage.message.senderInfoExt) {
                    contact = [[AccountInfo alloc] init];
                    contact.address = [lastMessage.message.senderInfoExt valueForKey:@"address"];
                    contact.avatar = [lastMessage.message.senderInfoExt valueForKey:@"avatar"];
                    contact.username = [lastMessage.message.senderInfoExt valueForKey:@"username"];
                    contact.stranger = NO;
                    contact.pub_key = lastMessage.messageOwer;
                    //Sync contacts
                    if (![[UserDBManager sharedManager] isFriendByAddress:contact.address] && !self.syncContacting) {
                        self.syncContacting = YES;
                        [[IMService instance] syncFriendsWithComlete:^(NSError *erro, id data) {
                            self.syncContacting = NO;
                        }];
                    }
                }
                recentModel = [[RecentChatModel alloc] init];
                recentModel.headUrl = contact.avatar;
                recentModel.name = contact.username;
                recentModel.talkType = GJGCChatFriendTalkTypePrivate;
                recentModel.time = [NSString stringWithFormat:@"%lld",(long long)([[NSDate date] timeIntervalSince1970] * 1000)];
                recentModel.identifier = lastMessage.messageOwer;
                recentModel.content = lastMessage.message.content;
                recentModel.unReadCount = messageCount;
                recentModel.chatUser = contact;
                
                recentModel.content = [GJGCChatFriendConstans lastContentMessageWithType:lastMessage.messageType textMessage:lastMessage.message.content];
                recentModel.snapChatDeleteTime = (int)snapChatTime;
                
                if (lastMessage.message.type == 11) {
                    recentModel.unReadCount = 0;
                    NSString *content;
                    NSString *snapChatDeleteTime = lastMessage.message.content;
                    if (lastMessage.message.content.length > 1 || [lastMessage.message.content integerValue] > 0) { //带时间
                        content = @"开启隐私模式";
                    } else{
                        content = @"关闭隐私模式";
                    }
                    recentModel.content = content;
                    recentModel.snapChatDeleteTime = [snapChatDeleteTime intValue];
                }
                [[RecentChatDBManager sharedManager] save:recentModel];
            } else{
                
                recentModel.content = [GJGCChatFriendConstans lastContentMessageWithType:lastMessage.messageType textMessage:lastMessage.message.content];
                int unRead = recentModel.unReadCount;
                unRead += messageCount;
                
                if ([[SessionManager sharedManager].chatSession isEqualToString:recentModel.identifier] ||
                    recentModel.notifyStatus) {
                    unRead = 0;
                }
                
                if (recentModel.stranger) {
                    recentModel.stranger = NO;
                    recentModel.chatUser.stranger = NO;
                }
                recentModel.unReadCount = unRead;
                recentModel.snapChatDeleteTime = (int)snapChatTime;
                
                recentModel.time = [NSString stringWithFormat:@"%lld",(long long)([[NSDate date] timeIntervalSince1970] * 1000)];
                if (lastMessage.message.type == 11) {
                    NSString *content;
                    NSString *snapChatDeleteTime = lastMessage.message.content;
                    if (lastMessage.message.content.length > 1 || [lastMessage.message.content integerValue] > 0) { //带时间
                        content = @"开启隐私模式";
                    } else{
                        content = @"关闭隐私模式";
                    }
                    
                    recentModel.content = content;
                    recentModel.snapChatDeleteTime = [snapChatDeleteTime intValue];
                }
                NSMutableDictionary *fieldsValues = [NSMutableDictionary dictionary];
                [fieldsValues safeSetObject:@(unRead) forKey:@"unread_count"];
                [fieldsValues safeSetObject:recentModel.content forKey:@"content"];
                [fieldsValues safeSetObject:recentModel.time forKey:@"last_time"];
                if (recentModel.stranger) {
                    [fieldsValues safeSetObject:@(NO) forKey:@"stranger"];
                }
                
                [[RecentChatDBManager sharedManager] customUpdateRecentChatTableWithFieldsValues:fieldsValues withIdentifier:recentModel.identifier];
                
                [[RecentChatDBManager sharedManager] openOrCloseSnapChatWithTime:recentModel.snapChatDeleteTime chatIdentifer:recentModel.identifier];
            }
        }
            break;
            
        case GJGCChatFriendTalkTypeGroup:
        {
            recentModel = [[SessionManager sharedManager] getRecentChatWithIdentifier:lastMessage.messageOwer];
            if (!recentModel) {
                
                LMGroupInfo *group = [[GroupDBManager sharedManager] getgroupByGroupIdentifier:lastMessage.messageOwer];
                recentModel = [[RecentChatModel alloc] init];
                recentModel.headUrl = group.avatarUrl;
                recentModel.name = group.groupName;
                recentModel.time = [NSString stringWithFormat:@"%lld",(long long)([[NSDate date] timeIntervalSince1970] * 1000)];
                recentModel.identifier = lastMessage.messageOwer;
                recentModel.content = lastMessage.message.content;
                recentModel.unReadCount = messageCount;
                
                NSString *sendName = nil;
                AccountInfo *senderUser = [group.addressMemberDict valueForKey:[lastMessage.message.senderInfoExt valueForKey:@"address"]];
                if (senderUser) {
                    sendName = senderUser.username;
                } else{
                    sendName = [lastMessage.message.senderInfoExt valueForKey:@"username"];
                }
                recentModel.content = [GJGCChatFriendConstans lastContentMessageWithType:lastMessage.messageType textMessage:lastMessage.message.content senderUserName:sendName];
                recentModel.talkType = GJGCChatFriendTalkTypeGroup;
                recentModel.chatGroupInfo = group;
                [[RecentChatDBManager sharedManager] save:recentModel];
            } else{
                NSString *sendName = nil;
                AccountInfo *senderUser = [recentModel.chatGroupInfo.addressMemberDict valueForKey:[lastMessage.message.senderInfoExt valueForKey:@"address"]];
                if (senderUser) {
                    sendName = senderUser.groupShowName;
                } else{
                    sendName = [lastMessage.message.senderInfoExt valueForKey:@"username"];
                }
                recentModel.content = [GJGCChatFriendConstans lastContentMessageWithType:lastMessage.messageType textMessage:lastMessage.message.content senderUserName:sendName];
                int unRead = recentModel.unReadCount;
                unRead += messageCount;
                if ([[SessionManager sharedManager].chatSession isEqualToString:recentModel.identifier] ||
                    recentModel.notifyStatus) {
                    unRead = 0;
                }
                recentModel.unReadCount = unRead;
                recentModel.time = [NSString stringWithFormat:@"%lld",(long long)([[NSDate date] timeIntervalSince1970] * 1000)];
                
                NSMutableDictionary *fieldsValues = [NSMutableDictionary dictionary];
                [fieldsValues safeSetObject:@(unRead) forKey:@"unread_count"];
                [fieldsValues safeSetObject:recentModel.content forKey:@"content"];
                [fieldsValues safeSetObject:recentModel.time forKey:@"last_time"];
                
                [[RecentChatDBManager sharedManager] customUpdateRecentChatTableWithFieldsValues:fieldsValues withIdentifier:recentModel.identifier];
            }
        }
            break;
            
        case GJGCChatFriendTalkTypePostSystem:
        {
            
            recentModel = [[SessionManager sharedManager] getRecentChatWithIdentifier:@"connect"];
            if (recentModel) {
                int unRead = recentModel.unReadCount;
                unRead += messageCount;
                if ([[SessionManager sharedManager].chatSession isEqualToString:recentModel.identifier]) {
                    unRead = 0;
                }
                int long long time = [[NSDate date] timeIntervalSince1970] * 1000;
                NSString *last_time = [NSString stringWithFormat:@"%lld",time];
                recentModel.unReadCount = unRead;
                recentModel.time = last_time;
                recentModel.content = [GJGCChatFriendConstans lastContentMessageWithType:lastMessage.messageType textMessage:lastMessage.message.content];
                
                NSMutableDictionary *fieldsValues = [NSMutableDictionary dictionary];
                [fieldsValues safeSetObject:@(unRead) forKey:@"unread_count"];
                [fieldsValues safeSetObject:recentModel.content forKey:@"content"];
                [fieldsValues safeSetObject:recentModel.time forKey:@"last_time"];
                
                [[RecentChatDBManager sharedManager] customUpdateRecentChatTableWithFieldsValues:fieldsValues withIdentifier:recentModel.identifier];
                
            } else{
                recentModel = [[RecentChatModel alloc] init];
                recentModel.talkType = GJGCChatFriendTalkTypePostSystem;
                int long long time = [[NSDate date] timeIntervalSince1970] * 1000;
                recentModel.time = [NSString stringWithFormat:@"%lld",time];
                recentModel.unReadCount = messageCount;
                recentModel.name = @"Connect";
                recentModel.headUrl = @"connect_logo";
                recentModel.identifier = @"connect";
                recentModel.content = [GJGCChatFriendConstans lastContentMessageWithType:lastMessage.messageType textMessage:lastMessage.message.content];
                [[RecentChatDBManager sharedManager] save:recentModel];
            }
        }
            break;
        default:
            break;
    }
    [GCDQueue executeInMainQueue:^{
        if ([[SessionManager sharedManager].allRecentChats containsObject:recentModel]) {
            [[SessionManager sharedManager].allRecentChats moveObject:recentModel toIndex:recentModel.isTopChat?0:[SessionManager sharedManager].topChatCount];
        } else{
            [[SessionManager sharedManager].allRecentChats objectInsert:recentModel atIndex:recentModel.isTopChat?0:[SessionManager sharedManager].topChatCount];
        }
        if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
            [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
        }
        if (messageCount > 0) {
            if ([self.conversationListDelegate respondsToSelector:@selector(unreadMessageNumberDidChanged)]) {
                [self.conversationListDelegate unreadMessageNumberDidChanged];
            }
        }
    }];
    
}

- (void)getNewMessagesWithLastMessage:(ChatMessageInfo *)lastMessage newMessageCount:(int)messageCount  groupNoteMyself:(BOOL)groupNoteMyself{
    RecentChatModel *recentModel = [[SessionManager sharedManager] getRecentChatWithIdentifier:lastMessage.messageOwer];
    if (!recentModel) {
        LMGroupInfo *group = [[GroupDBManager sharedManager] getgroupByGroupIdentifier:lastMessage.messageOwer];
        recentModel = [[RecentChatModel alloc] init];
        recentModel.headUrl = group.avatarUrl;
        recentModel.name = group.groupName;
        recentModel.time = [NSString stringWithFormat:@"%lld",(long long)([[NSDate date] timeIntervalSince1970] * 1000)];
        recentModel.identifier = lastMessage.messageOwer;
        recentModel.content = lastMessage.message.content;
        recentModel.unReadCount = messageCount;
        recentModel.groupNoteMyself = groupNoteMyself;
        NSString *sendName = nil;
        AccountInfo *senderUser = [group.addressMemberDict valueForKey:[lastMessage.message.senderInfoExt valueForKey:@"address"]];
        if (senderUser) {
            sendName = senderUser.username;
        } else{
            sendName = [lastMessage.message.senderInfoExt valueForKey:@"username"];
        }
        recentModel.content = [GJGCChatFriendConstans lastContentMessageWithType:lastMessage.messageType textMessage:lastMessage.message.content senderUserName:sendName];
        recentModel.talkType = GJGCChatFriendTalkTypeGroup;
        recentModel.chatGroupInfo = group;
        [[RecentChatDBManager sharedManager] save:recentModel];
    } else{
        if ([[SessionManager sharedManager].chatSession isEqualToString:lastMessage.messageOwer]) {
            recentModel.groupNoteMyself = NO;
        } else{
            if (!recentModel.groupNoteMyself) {
                recentModel.groupNoteMyself = groupNoteMyself;
            }
        }
        NSString *sendName = nil;
        AccountInfo *senderUser = [recentModel.chatGroupInfo.addressMemberDict valueForKey:[lastMessage.message.senderInfoExt valueForKey:@"address"]];
        if (senderUser) {
            sendName = senderUser.groupShowName;
        } else{
            sendName = [lastMessage.message.senderInfoExt valueForKey:@"username"];
        }
        recentModel.content = [GJGCChatFriendConstans lastContentMessageWithType:lastMessage.messageType textMessage:lastMessage.message.content senderUserName:sendName];
        int unRead = recentModel.unReadCount;
        unRead += messageCount;
        if ([[SessionManager sharedManager].chatSession isEqualToString:recentModel.identifier] ||
            recentModel.notifyStatus) {
            unRead = 0;
        }
        recentModel.unReadCount = unRead;
        recentModel.time = [NSString stringWithFormat:@"%lld",(long long)([[NSDate date] timeIntervalSince1970] * 1000)];
        NSMutableDictionary *fieldsValues = [NSMutableDictionary dictionary];
        [fieldsValues safeSetObject:@(unRead) forKey:@"unread_count"];
        [fieldsValues safeSetObject:recentModel.content forKey:@"content"];
        [fieldsValues safeSetObject:recentModel.time forKey:@"last_time"];
        [fieldsValues safeSetObject:@(groupNoteMyself) forKey:@"notice"];
        
        [[RecentChatDBManager sharedManager] customUpdateRecentChatTableWithFieldsValues:fieldsValues withIdentifier:recentModel.identifier];
    }
    [GCDQueue executeInMainQueue:^{
        if ([[SessionManager sharedManager].allRecentChats containsObject:recentModel]) {
            [[SessionManager sharedManager].allRecentChats moveObject:recentModel toIndex:recentModel.isTopChat?0:[SessionManager sharedManager].topChatCount];
            DDLogInfo(@"get message :move model");
        } else{
            [[SessionManager sharedManager].allRecentChats objectInsert:recentModel atIndex:recentModel.isTopChat?0:[SessionManager sharedManager].topChatCount];
            DDLogInfo(@"get message :insert model");
        }
        if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
            [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
        }
        if (messageCount > 0) {
            if ([self.conversationListDelegate respondsToSelector:@selector(unreadMessageNumberDidChanged)]) {
                [self.conversationListDelegate unreadMessageNumberDidChanged];
            }
        }
    }];
    
}


- (void)sendMessage:(MMMessage *)message type:(GJGCChatFriendTalkType)type{
    
    NSString *lastContentString = nil;
    if (type == GJGCChatFriendTalkTypeGroup) {
        lastContentString = [GJGCChatFriendConstans lastContentMessageWithType:message.type textMessage:message.content senderUserName:[message.senderInfoExt valueForKey:@"username"]];
    } else{
        lastContentString = [GJGCChatFriendConstans lastContentMessageWithType:message.type textMessage:message.content];
    }
    if ([[message.ext valueForKey:@"luck_delete"] integerValue] > 0) {
        lastContentString = LMLocalizedString(@"Chat send a snap chat message", nil);
    }
    RecentChatModel *recentModel = [[RecentChatDBManager sharedManager] createNewChatWithIdentifier:message.publicKey groupChat:type == GJGCChatFriendTalkTypeGroup lastContentShowType:0 lastContent:lastContentString];
    
    if (recentModel.stranger && recentModel.talkType == GJGCChatFriendTalkTypePrivate) {
        recentModel.stranger = ![[UserDBManager sharedManager] isFriendByAddress:[KeyHandle getAddressByPubkey:recentModel.identifier]];
        recentModel.chatUser.stranger = recentModel.stranger;
    }
    [GCDQueue executeInMainQueue:^{
        if ([[SessionManager sharedManager].allRecentChats containsObject:recentModel]) {
            [[SessionManager sharedManager].allRecentChats moveObject:recentModel toIndex:recentModel.isTopChat?0:[SessionManager sharedManager].topChatCount];
        } else{
            [[SessionManager sharedManager].allRecentChats objectInsert:recentModel atIndex:recentModel.isTopChat?0:[SessionManager sharedManager].topChatCount];
        }
        
        if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
            [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
        }
    }];
}

- (void)chatWithNewFriend:(AccountInfo *)chatUser{
    if (!chatUser) {
        return;
    }
    MMMessage *message = [[MMMessage alloc] init];
    NSDictionary *senderInfoExt = @{@"address":chatUser.address,
                                    @"avatar":chatUser.avatar,
                                    @"username":chatUser.username};
    message.senderInfoExt = senderInfoExt;
    message.type = GJGCChatFriendContentTypeText;
    long int time = [[UserDBManager sharedManager] getRequestTimeByUserPublickey:chatUser.pub_key];
    NSString *tips = [[UserDBManager sharedManager] getRequestTipsByUserPublickey:chatUser.pub_key];
    chatUser.message = tips;
    if (time) {
        message.sendtime  = time;
    } else{
        message.sendtime  = (long int)([[NSDate date] timeIntervalSince1970] * 1000);
    }
    message.message_id =  [ConnectTool generateMessageId];
    message.content = !GJCFStringIsNull(chatUser.message)?chatUser.message:[NSString stringWithFormat:LMLocalizedString(@"Link Hello I am", nil),chatUser.username];
    message.publicKey = [[LKUserCenter shareCenter] currentLoginUser].pub_key;
    message.user_id = [[LKUserCenter shareCenter] currentLoginUser].address;
    message.sendstatus = GJGCChatFriendSendMessageStatusSuccess;
    ChatMessageInfo *messageInfo = [[ChatMessageInfo alloc] init];
    messageInfo.messageId = message.message_id;
    messageInfo.messageType = message.type;
    messageInfo.createTime = (NSInteger)message.sendtime;
    messageInfo.messageOwer = chatUser.pub_key;
    messageInfo.sendstatus = GJGCChatFriendSendMessageStatusSuccess;
    messageInfo.message = message;
    messageInfo.snapTime = 0;
    messageInfo.readTime = 0;
    [[MessageDBManager sharedManager] saveMessage:messageInfo];
    [self getNewMessagesWithLastMessage:messageInfo newMessageCount:1 type:GJGCChatFriendTalkTypePrivate withSnapChatTime:0];
}

- (void)getAllConversation{
    
}

- (BOOL)deleteConversation:(RecentChatModel *)conversationModel{
    if (!conversationModel) {
        return NO;
    }
    [[RecentChatDBManager sharedManager] deleteByIdentifier:conversationModel.identifier];
    if (conversationModel.talkType != GJGCChatFriendTalkTypeGroup) {
        [[CIImageCacheManager sharedInstance] removeGroupAvatarCacheWithGroupIdentifier:conversationModel.identifier];
        [[IMService instance] addNewSessionWithAddress:conversationModel.chatUser.address complete:^(NSError *erro, id data) {
        }];
        [ChatMessageFileManager deleteRecentChatAllMessageFilesByAddress:conversationModel.chatUser.address];
    } else{
        [ChatMessageFileManager deleteRecentChatAllMessageFilesByAddress:conversationModel.identifier];
    }
    if (conversationModel.isTopChat && [SessionManager sharedManager].topChatCount >= 1) {
        [SessionManager sharedManager].topChatCount--;
    }
    if (conversationModel && conversationModel.identifier) {
        [[RecentChatDBManager sharedManager] deleteByIdentifier:conversationModel.identifier];
        [[MessageDBManager sharedManager] deleteAllMessageByMessageOwer:conversationModel.identifier]; //删除所有消息
    }
    
    if (conversationModel.unReadCount > 0) {
        [GCDQueue executeInMainQueue:^{
            if ([self.conversationListDelegate respondsToSelector:@selector(unreadMessageNumberDidChanged)]) {
                [self.conversationListDelegate unreadMessageNumberDidChanged];
            }
        }];
    }

    return YES;
}

- (void)setConversationMute:(RecentChatModel *)model complete:(void (^)(BOOL complete))complete{
    BOOL notify = model.notifyStatus;
    if (model.talkType != GJGCChatFriendTalkTypeGroup) {
        [[IMService instance] openOrCloseSesionMuteWithAddress:model.chatUser.address mute:model.notifyStatus complete:^(NSError *erro, id data) {
            if (!erro) {
                if (!notify) {
                    [[RecentChatDBManager sharedManager] setMuteWithIdentifer:model.identifier];
                    if (model.unReadCount) {
                        model.notifyStatus = YES;
                        model.unReadCount = 0;
                        [GCDQueue executeInMainQueue:^{
                            if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                                [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
                            }
                            if ([self.conversationListDelegate respondsToSelector:@selector(unreadMessageNumberDidChanged)]) {
                                [self.conversationListDelegate unreadMessageNumberDidChanged];
                            }
                        }];
                    } else{
                        model.notifyStatus = YES;
                        [GCDQueue executeInMainQueue:^{
                            if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                                [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
                            }
                        }];
                    }
                } else {
                    [[RecentChatDBManager sharedManager] removeMuteWithIdentifer:model.identifier];
                    model.notifyStatus = NO;
                    [GCDQueue executeInMainQueue:^{
                        if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                            [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
                        }
                    }];
                }
                if (complete) {
                    complete(YES);
                }
            } else{
                if (complete) {
                    complete(NO);
                }
            }
        }];
    } else {
        [SetGlobalHandler GroupChatSetMuteWithIdentifer:model.identifier mute:!notify complete:^(NSError *erro) {
            if (!erro) {
                if (!notify) {
                    [[RecentChatDBManager sharedManager] setMuteWithIdentifer:model.identifier];
                    if (model.unReadCount) {
                        model.notifyStatus = YES;
                        model.unReadCount = 0;
                        [GCDQueue executeInMainQueue:^{
                            if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                                [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
                            }
                            if ([self.conversationListDelegate respondsToSelector:@selector(unreadMessageNumberDidChanged)]) {
                                [self.conversationListDelegate unreadMessageNumberDidChanged];
                            }
                        }];
                    } else{
                        model.notifyStatus = YES;
                        [GCDQueue executeInMainQueue:^{
                            if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                                [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
                            }
                        }];
                    }
                } else {
                    [[RecentChatDBManager sharedManager] removeMuteWithIdentifer:model.identifier];
                    model.notifyStatus = NO;
                    [GCDQueue executeInMainQueue:^{
                        if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                            [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
                        }
                    }];
                }
                if (complete) {
                    complete(YES);
                }
            } else {
                if (complete) {
                    complete(NO);
                }
            }
        }];
    }
}

- (void)markAllMessagesAsRead:(RecentChatModel *)conversation{
    if (conversation) {
        conversation.unReadCount = 0;
        [[RecentChatDBManager sharedManager] clearUnReadCountWithIdetifier:conversation.identifier];
        [GCDQueue executeInMainQueue:^{
            if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
            }
            if ([self.conversationListDelegate respondsToSelector:@selector(unreadMessageNumberDidChanged)]) {
                [self.conversationListDelegate unreadMessageNumberDidChanged];
            }
        }];
    }
}

- (void)setRecentStrangerStatusWithIdentifier:(NSString *)identifier stranger:(BOOL)stranger{
    if (GJCFStringIsNull(identifier)) {
        return;
    }
    RecentChatModel *model = [[SessionManager sharedManager] getRecentChatWithIdentifier:identifier];
    if (model && model.stranger != stranger) {
        model.stranger = stranger;
        [[RecentChatDBManager sharedManager] updataStrangerStatus:stranger idetifier:identifier];
        if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
            [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
        }
    }
}

- (void)markConversionMessagesAsReadWithIdentifier:(NSString *)conversationIdentifier{
    if (GJCFStringIsNull(conversationIdentifier)) {
        return;
    }
    RecentChatModel *model = [[SessionManager sharedManager] getRecentChatWithIdentifier:conversationIdentifier];
    [self markAllMessagesAsRead:model];
}

- (void)clearConversionUnreadAndGroupNoteWithIdentifier:(NSString *)conversationIdentifier{
    if (GJCFStringIsNull(conversationIdentifier)) {
        return;
    }
    BOOL needSyncBadge = NO;
    BOOL needReload = NO;
    RecentChatModel *recentModel = [[SessionManager sharedManager] getRecentChatWithIdentifier:conversationIdentifier];
    if (recentModel.unReadCount != 0) {
        recentModel.unReadCount = 0;
        [[RecentChatDBManager sharedManager] clearUnReadCountWithIdetifier:conversationIdentifier];
        needSyncBadge = YES;
        needReload = YES;
    }
    
    if (recentModel.groupNoteMyself) {
        recentModel.groupNoteMyself = NO;
        [[RecentChatDBManager sharedManager] clearGroupNoteMyselfWithIdentifer:recentModel.identifier];
        needReload = YES;
    }
    [GCDQueue executeInMainQueue:^{
        if (needReload) {
            if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
            }
        }
        if (needSyncBadge) {
            if ([self.conversationListDelegate respondsToSelector:@selector(unreadMessageNumberDidChangedNeedSyncbadge)]) {
                [self.conversationListDelegate unreadMessageNumberDidChangedNeedSyncbadge];
            }
        }
    }];
}


#pragma mark -groupAvatarChange
- (void)groupAvatarChange{
    [GCDQueue executeInMainQueue:^{
        if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
            [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
        }
    }];
}

- (void)groupNicknameChange{
    [self getAllConversationFromDB];
}

- (void)getOfflineComplete{
//    [self getAllConversationFromDB];
}

- (void)clearUnReadCount:(NSNotification *)note{
    RecentChatModel *model = note.object;
    NSInteger index = NSNotFound;
    index = [[SessionManager sharedManager].allRecentChats indexOfObject:model];
    model = [[SessionManager sharedManager].allRecentChats objectAtIndexCheck:index];
    model.unReadCount = 0;
    [GCDQueue executeInMainQueue:^{
        if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
            [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
        }
        if ([self.conversationListDelegate respondsToSelector:@selector(unreadMessageNumberDidChanged)]) {
            [self.conversationListDelegate unreadMessageNumberDidChanged];
        }
    }];
}


- (void)haveDraft:(NSNotification *)note{
    /*
     @{@"identifier":_chatSession,
     @"draft":draft})
     */
    NSString *identifier = [note.object valueForKey:@"identifier"];
    NSString *draft = [note.object valueForKey:@"draft"];
    RecentChatModel *model = [[SessionManager sharedManager] getRecentChatWithIdentifier:identifier];
    model.draft = draft;
    if (model) {
        [GCDQueue executeInMainQueue:^{
            if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
            }
        }];
    }
}


- (void)muteChange:(NSNotification *)note{
    NSString *chatIdentifier = note.object;
    if (GJCFStringIsNull(chatIdentifier)) {
        return;
    }
    RecentChatModel *findModel = [[SessionManager sharedManager] getRecentChatWithIdentifier:chatIdentifier];
    if (findModel) {
        findModel.notifyStatus = !findModel.notifyStatus;
        [GCDQueue executeInMainQueue:^{
            if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
            }
        }];
    }
}

/**
 @{@"identifier":publiKeyOrGroupid,
 @"status":@(NO)};
 */
- (void)topChatStatusChange:(NSNotification *)note{
    
    NSString *identifier = [note.object valueForKey:@"identifier"];
    BOOL topChat = [[note.object valueForKey:@"status"] boolValue];
    RecentChatModel *findModel = [[SessionManager sharedManager] getRecentChatWithIdentifier:identifier];
    findModel.isTopChat = topChat;

    if (findModel) {
        if (topChat) {
            [[SessionManager sharedManager].allRecentChats moveObject:findModel toIndex:0];
        } else{
            [[SessionManager sharedManager].allRecentChats moveObject:findModel toIndex:[SessionManager sharedManager].topChatCount];
        }
    }
    [GCDQueue executeInMainQueue:^{
        if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
            [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
        }
    }];
}


- (void)deleteRecentChat:(NSNotification *)note{
    NSString *dentifier = note.object;
    if (GJCFStringIsNull(dentifier)) {
        return;
    }
    RecentChatModel *deleteModel = [[SessionManager sharedManager] getRecentChatWithIdentifier:dentifier];
    if (deleteModel) {
        [[SessionManager sharedManager].allRecentChats removeObject:deleteModel];
        [GCDQueue executeInMainQueue:^{
            if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
            }
        }];
    }
}


#pragma mark - sendMessageSuccess
- (void)sendMessageSuccess:(NSNotification *)note{
    
    NSString *identifier = note.object;
    if (GJCFStringIsNull(identifier)) {
        return;
    }
    RecentChatModel *findModel = [[SessionManager sharedManager] getRecentChatWithIdentifier:identifier];
    if (findModel) {
        [GCDQueue executeInMainQueue:^{
            if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
            }
        }];
    }
}

- (void)recentChatChange:(NSNotification *)note{
    RecentChatModel *recentChat = note.object;
    if (!recentChat) {
        return;
    }
    NSInteger index = [[SessionManager sharedManager].allRecentChats indexOfObject:recentChat];
    if (recentChat.talkType == GJGCChatFriendTalkTypeGroup) {
        if (recentChat.chatGroupInfo.groupMembers.count == 0) {
            LMGroupInfo *group = [[GroupDBManager sharedManager] getgroupByGroupIdentifier:recentChat.identifier];
            recentChat.chatGroupInfo = group;
            recentChat.name = group.groupName;
        }
    }
    if (index != NSNotFound) {
        [[SessionManager sharedManager].allRecentChats moveObject:recentChat toIndex:recentChat.isTopChat?0:[SessionManager sharedManager].topChatCount];
    } else{
        NSInteger index = recentChat.isTopChat?0:[SessionManager sharedManager].topChatCount;
        [[SessionManager sharedManager].allRecentChats objectInsert:recentChat atIndex:index];
    }
    
    
    
    [GCDQueue executeInMainQueue:^{
        if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
            [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
        }
        if ([self.conversationListDelegate respondsToSelector:@selector(unreadMessageNumberDidChanged)]) {
            [self.conversationListDelegate unreadMessageNumberDidChanged];
        }
    }];
    
}

- (void)ContactInfoChange:(NSNotification *)note{
    AccountInfo *changeUser = note.object;
    if (!changeUser) {
        return;
    }
    RecentChatModel *findModel = [[SessionManager sharedManager] getRecentChatWithIdentifier:changeUser.pub_key];
    if (findModel) {
        findModel.name = changeUser.normalShowName;
        findModel.headUrl = changeUser.avatar;
        findModel.chatUser = changeUser;
        
        [GCDQueue executeInMainQueue:^{
            if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
            }
        }];
    }
}


- (void)GroupInfoChange:(NSNotification *)note{
    NSString *groupIdentifer = note.object;
    if (GJCFStringIsNull(groupIdentifer)) {
        return;
    }
    RecentChatModel *findModel = [[SessionManager sharedManager] getRecentChatWithIdentifier:groupIdentifer];
    if (findModel) {
        LMGroupInfo *group = [[GroupDBManager sharedManager] getgroupByGroupIdentifier:groupIdentifer];
        findModel.name = group.groupName;
        findModel.chatGroupInfo = group;
        [[CIImageCacheManager sharedInstance] removeGroupAvatarCacheWithGroupIdentifier:findModel.identifier];
        [GCDQueue executeInMainQueue:^{
            if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
            }
        }];
    }
}

- (void)quitGroup:(NSNotification *)note
{
    NSString *groupid = note.object;
    if (GJCFStringIsNull(groupid)) {
        return;
    }
    RecentChatModel *model = [[SessionManager sharedManager] getRecentChatWithIdentifier:groupid];
    if (model) {
        [ChatMessageFileManager deleteRecentChatAllMessageFilesByAddress:groupid];
        [[RecentChatDBManager sharedManager] deleteByIdentifier:groupid];
        [[MessageDBManager sharedManager] deleteAllMessageByMessageOwer:groupid];
        [[SessionManager sharedManager] removeRecentChatWithIdentifier:model.identifier];
        
        if (model.talkType == GJGCChatFriendTalkTypeGroup) {
            [[GroupDBManager sharedManager] deletegroupWithGroupId:model.identifier];
        }
        
        [GCDQueue executeInMainQueue:^{
            if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
            }
            if ([self.conversationListDelegate respondsToSelector:@selector(unreadMessageNumberDidChanged)]) {
                [self.conversationListDelegate unreadMessageNumberDidChanged];
            }
        }];

    }
}


- (void)enterForeground{
    [GCDQueue executeInMainQueue:^{
        if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
            [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
        }
        if ([self.conversationListDelegate respondsToSelector:@selector(unreadMessageNumberDidChanged)]) {
            [self.conversationListDelegate unreadMessageNumberDidChanged];
        }
    }];
}


- (void)acceptRequest:(NSNotification *)note{
    AccountInfo *user = note.object;
    [self chatWithNewFriend:user];
}


- (void)deleteUser:(NSNotification *)note{
    AccountInfo *willDeleteUser = (AccountInfo *)note.object;
    if (willDeleteUser) {
        [[SessionManager sharedManager] removeRecentChatWithIdentifier:willDeleteUser.pub_key];
        [GCDQueue executeInMainQueue:^{
            if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
            }
            if ([self.conversationListDelegate respondsToSelector:@selector(unreadMessageNumberDidChanged)]) {
                [self.conversationListDelegate unreadMessageNumberDidChanged];
            }
        }];
    }
}

- (void)friendListChange:(NSNotification *)note{
    BOOL __block changeFlag = NO;
    @synchronized([SessionManager sharedManager].allRecentChats) {
        for (RecentChatModel *model in [SessionManager sharedManager].allRecentChats) {
            if (model.talkType != GJGCChatFriendTalkTypeGroup && !model.chatUser) {
                AccountInfo *chatUser = [[UserDBManager sharedManager] getUserByPublickey:model.identifier];
                model.chatUser = chatUser;
                if (!model.name) {
                    model.name = chatUser.username;
                }
                if (!model.headUrl) {
                    model.headUrl = chatUser.avatar;
                }
                changeFlag = YES;
            } else if(!model.chatGroupInfo){
                LMGroupInfo *groupInfo = [[GroupDBManager sharedManager] getgroupByGroupIdentifier:model.identifier];
                model.chatGroupInfo = groupInfo;
                if (!model.name) {
                    model.name = groupInfo.groupName;
                }
                changeFlag = YES;
            }
        }
    }

    if (changeFlag) {
        [GCDQueue executeInMainQueue:^{
            if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
            }
            if ([self.conversationListDelegate respondsToSelector:@selector(unreadMessageNumberDidChanged)]) {
                [self.conversationListDelegate unreadMessageNumberDidChanged];
            }
        }];
    }
}

- (void)getNewMessageToUpdateUnreadCountWithRecentChatIdentifier:(NSString *)identifier{
    if (GJCFStringIsNull(identifier)) {
        return;
    }
    RecentChatModel *model = [[SessionManager sharedManager] getRecentChatWithIdentifier:identifier];
    model.unReadCount ++;
    [[RecentChatDBManager sharedManager] updataUnReadCount:model.unReadCount idetifier:identifier];
    if (model) {
        [GCDQueue executeInMainQueue:^{
            if ([self.conversationListDelegate respondsToSelector:@selector(conversationListDidChanged:)]) {
                [self.conversationListDelegate conversationListDidChanged:[SessionManager sharedManager].allRecentChats];
            }
            if ([self.conversationListDelegate respondsToSelector:@selector(unreadMessageNumberDidChanged)]) {
                [self.conversationListDelegate unreadMessageNumberDidChanged];
            }
        }];
    }
}

@end
