#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, KCEmoteProvider) {
    KCEmoteProviderKick = 0,
    KCEmoteProvider7TV,
};

@interface KCEmote : NSObject
@property (nonatomic, copy) NSString *name;        // the word in the chat
@property (nonatomic, copy) NSString *emoteId;
@property (nonatomic, copy) NSString *url1x;
@property (nonatomic, copy) NSString *url2x;
@property (nonatomic) NSInteger width;             // points at 1x (28 x 28 when unknown)
@property (nonatomic) NSInteger height;
@property (nonatomic) BOOL animated;
@property (nonatomic) BOOL zeroWidth;              // drawn over the emote before it (7TV)
@property (nonatomic) KCEmoteProvider provider;
- (NSString *)urlForScale:(CGFloat)scale;          // 1x or 2x, as the screen needs
- (NSString *)providerName;                        // "Kick", "7TV"
@end

// Posted on the main thread when emotes arrived (a chat redraws)
extern NSString * const KCEmotesDidChangeNotification;

// Kick's own emotes (every message names them by id) and the 7TV emotes many Kick channels use, which arrive as plain
// words. Lookups are safe from any thread; loading happens on the main thread.
@interface KCEmoteStore : NSObject

+ (instancetype)shared;

- (void)loadGlobalsIfNeeded;                                             // 7TV's global set, once in a while
- (void)loadChannel:(NSString *)channelId account:(NSString *)accountId;  // a channel's 7TV set (one at a time)

// 7TV emote for a word (the channel's set first, then the global one), nil for an ordinary word
- (KCEmote *)thirdPartyEmoteNamed:(NSString *)word channelId:(NSString *)channelId;
// A Kick emote by its id (from the message text); `animated` = may play (the picture is a GIF either way)
+ (KCEmote *)kickEmoteWithId:(NSString *)emoteId name:(NSString *)name animated:(BOOL)animated;

@end
