#import <Foundation/Foundation.h>
#import "KCHTTP.h"
#import "KCModels.h"

// One page of a list: the items, and the cursor for the next page (nil = that was the last one)
typedef void (^KCListCompletion)(NSArray *items, NSString *nextCursor, NSError *error);

// Clip periods
extern NSString * const KCClipPeriodDay;
extern NSString * const KCClipPeriodWeek;
extern NSString * const KCClipPeriodMonth;
extern NSString * const KCClipPeriodAll;

// Kick's web API as an anonymous visitor: everything the app shows without an account.
// Completion blocks run on the main thread; a cancelled task never calls back.
@interface KCAPI : NSObject

// A GET of a path on kick.com ("/api/v2/channels/xqc") with the JSON answer
+ (KCHTTPTask *)get:(NSString *)path completion:(void (^)(id json, NSError *error))completion;

// Browsing (KCStream / KCCategory items). The language filter of the settings applies to streams.
+ (KCHTTPTask *)topStreamsAfter:(NSString *)cursor completion:(KCListCompletion)completion;
+ (KCHTTPTask *)topCategoriesAfter:(NSString *)cursor completion:(KCListCompletion)completion;
+ (KCHTTPTask *)streamsForCategory:(KCCategory *)category after:(NSString *)cursor completion:(KCListCompletion)completion;
+ (KCHTTPTask *)category:(NSString *)slug completion:(void (^)(KCCategory *category, NSError *error))completion;

// Search: KCChannel and KCCategory items
+ (KCHTTPTask *)search:(NSString *)text completion:(void (^)(NSArray *channels, NSArray *categories, NSError *error))completion;

// Channels
+ (KCHTTPTask *)channel:(NSString *)slug completion:(void (^)(KCChannel *channel, NSError *error))completion;
// Several at once (the favourites; a few requests run side by side): channels that do not exist any more are left out
+ (KCHTTPTask *)channels:(NSArray *)slugs completion:(void (^)(NSArray *channels, NSError *error))completion;
// The channel's recordings, newest first (one page)
+ (KCHTTPTask *)videosForChannel:(NSString *)slug after:(NSString *)cursor completion:(KCListCompletion)completion;
+ (KCHTTPTask *)clipsForChannel:(NSString *)slug period:(NSString *)period after:(NSString *)cursor completion:(KCListCompletion)completion;
+ (KCHTTPTask *)clipsForCategory:(KCCategory *)category period:(NSString *)period after:(NSString *)cursor completion:(KCListCompletion)completion;

// Chat: the latest messages of a channel (KCChatMessage, oldest first), shown before the live chat starts
+ (KCHTTPTask *)recentMessagesForChannelId:(NSString *)channelId completion:(void (^)(NSArray *messages, NSError *error))completion;
// ...and the chat of a past broadcast: the messages of the few seconds from `time` on, oldest first
+ (KCHTTPTask *)chatReplayForChannelId:(NSString *)channelId at:(NSDate *)time completion:(void (^)(NSArray *messages, NSError *error))completion;

// Whether a stream matches the language filter of the settings (Kick names languages in English: "Czech")
+ (BOOL)streamMatchesLanguageFilter:(KCStream *)stream;

@end
