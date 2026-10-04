#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, KCChatKind) {
    KCChatKindMessage = 0,     // somebody wrote something
    KCChatKindNotice,          // a line from the system or the app: grey text, no author
    KCChatKindUserNotice,      // a subscription, a gift, a host...: systemText
};

// A Kick emote inside the text (Kick writes them into messages as [emote:ID:name]; the name stays in the text)
@interface KCChatEmoteRange : NSObject
@property (nonatomic, copy) NSString *emoteId;
@property (nonatomic) NSRange range;                   // in UTF-16 units of `text`
@end

// One entry of a chat: a message, or a notice
@interface KCChatMessage : NSObject

@property (nonatomic) KCChatKind kind;
@property (nonatomic, copy) NSString *messageId;
@property (nonatomic, copy) NSString *slug;             // the author's channel name (lower case)
@property (nonatomic, copy) NSString *displayName;      // the author's user name as written
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *text;             // what the user wrote ("" for pure notices)
@property (nonatomic, copy) NSString *systemText;       // "X subscribed for 12 months", "Chat was cleared"...
@property (nonatomic, copy) NSString *colorHex;         // the user's name colour, "#RRGGBB" or nil
@property (nonatomic, copy) NSString *noticeType;       // sub, subgift, host...
@property (nonatomic, copy) NSString *replyParentName;  // when the message answers another one
@property (nonatomic, copy) NSString *replyParentText;
@property (nonatomic, strong) NSArray *badges;          // @[ @[name, image URL] ]
@property (nonatomic, strong) NSArray *emotes;          // KCChatEmoteRange, by position
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic) NSTimeInterval replayOffset;      // in a chat replay: the moment in the video (-1 = live)
@property (nonatomic) BOOL isDeleted;                   // removed by a moderator

// Layout cache used by the chat view (KCChatLayout); dropped when the width or the style changes
@property (nonatomic, strong) id layout;
@property (nonatomic) CGFloat layoutWidth;
@property (nonatomic) NSUInteger layoutStyleVersion;

// A chat message as Kick sends it (live over the WebSocket, or from the message history); nil for anything else
+ (instancetype)messageFromKick:(NSDictionary *)data;
// A grey line of the system or the app
+ (instancetype)noticeWithText:(NSString *)text;
// A subscription, a gift, a host... (shown highlighted)
+ (instancetype)userNoticeWithText:(NSString *)text type:(NSString *)type;

- (NSString *)nameForDisplay;                           // user name (slug) when they differ beyond case
- (NSString *)colorKey;                                 // the name's colour, or a stable default colour from the name

@end
