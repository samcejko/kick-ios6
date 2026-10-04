#import <Foundation/Foundation.h>
#import "KCChatMessage.h"

typedef NS_ENUM(NSInteger, KCChatState) {
    KCChatStateDisconnected = 0,
    KCChatStateConnecting,
    KCChatStateConnected,       // subscribed to the chatroom
    KCChatStateReconnecting,    // lost the connection, trying again in a moment
};

@class KCChat;

// Everything arrives on the main thread.
@protocol KCChatDelegate <NSObject>
- (void)chat:(KCChat *)chat didReceiveMessages:(NSArray *)messages;               // KCChatMessage, in order, batched
- (void)chat:(KCChat *)chat didChangeState:(KCChatState)state;
@optional
// keys: emoteOnly, subscribersOnly (NSNumber BOOL), followersOnly (minutes, -1 = off), slow (seconds, 0 = off)
- (void)chat:(KCChat *)chat didUpdateRoomState:(NSDictionary *)state;
// A moderator removed the messages of a user (slug nil = the whole chat); seconds > 0 = timeout, 0 = ban or clear
- (void)chat:(KCChat *)chat didClearMessagesOfUser:(NSString *)slug seconds:(NSInteger)seconds;
- (void)chat:(KCChat *)chat didDeleteMessageWithId:(NSString *)messageId;
@end

// The live chat of one channel, read as a visitor through Kick's Pusher WebSocket (TLS through the app's own stack).
// Reconnects by itself and keeps the connection alive.
@interface KCChat : NSObject

- (instancetype)initWithChatroomId:(NSString *)chatroomId channel:(NSString *)slug;

@property (nonatomic, weak) id<KCChatDelegate> delegate;
@property (nonatomic, readonly, copy) NSString *channel;
@property (nonatomic, readonly, copy) NSString *chatroomId;
@property (nonatomic, readonly) KCChatState state;

- (void)connect;
- (void)disconnect;

@end
