#import <Foundation/Foundation.h>

// Plain model objects filled from Kick's JSON. Missing fields stay nil / 0.
// Kick serves its pictures as WebP only; KCImageLoader decodes them.

@interface KCStream : NSObject
@property (nonatomic, copy) NSString *streamId;         // the livestream's id
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *slug;             // the channel as in URLs (lower case)
@property (nonatomic, copy) NSString *displayName;      // the user name as written ("xQc")
@property (nonatomic, copy) NSString *userId;           // the channel's id
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, copy) NSString *categoryId;
@property (nonatomic, copy) NSString *categoryName;
@property (nonatomic, copy) NSString *categorySlug;
@property (nonatomic, copy) NSString *language;         // as Kick names it: "English", "Czech"...
@property (nonatomic, copy) NSString *cursor;
@property (nonatomic, strong) NSArray *tags;            // names
@property (nonatomic, strong) NSDictionary *thumbnails; // NSNumber width -> URL (Kick refreshes the picture while live)
@property (nonatomic, strong) NSDate *startedAt;
@property (nonatomic) NSInteger viewers;
@property (nonatomic) BOOL isMature;

// An entry of the live directory (also a category's streams and search results): the channel is nested in it
+ (instancetype)streamFromKick:(NSDictionary *)item;
// The `livestream` object of a channel, with that channel
+ (instancetype)streamFromLivestream:(NSDictionary *)live channel:(NSDictionary *)channel;
- (NSString *)nameForDisplay;                           // the user name; with the slug when they differ beyond case
- (NSString *)previewURLWithWidth:(NSInteger)width height:(NSInteger)height;   // the smallest preview at least this wide
@end

@interface KCCategory : NSObject
@property (nonatomic, copy) NSString *categoryId;
@property (nonatomic, copy) NSString *slug;             // what the API looks a category up by ("just-chatting")
@property (nonatomic, copy) NSString *name;             // "Just Chatting"
@property (nonatomic, copy) NSString *imageURL;         // the card picture
@property (nonatomic, copy) NSString *parentName;       // the group it belongs to ("IRL", "Games")
@property (nonatomic, copy) NSString *cursor;
@property (nonatomic) NSInteger viewers;
@property (nonatomic) NSInteger followers;
+ (instancetype)categoryFromKick:(NSDictionary *)node;
- (NSString *)title;
@end

@interface KCChannel : NSObject
@property (nonatomic, copy) NSString *userId;           // the channel's id (chat history)
@property (nonatomic, copy) NSString *accountId;        // the owner's user id (7TV emotes)
@property (nonatomic, copy) NSString *slug;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *bio;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, copy) NSString *bannerURL;
@property (nonatomic, copy) NSString *offlineImageURL;
@property (nonatomic, copy) NSString *chatroomId;       // where its live chat is
@property (nonatomic, copy) NSString *playbackURL;      // the live stream's HLS master (carries its own token)
@property (nonatomic, copy) NSString *lastCategoryName;
@property (nonatomic, strong) KCStream *stream;         // nil when offline
@property (nonatomic) NSInteger followers;
@property (nonatomic) BOOL isVerified;
@property (nonatomic) BOOL isAffiliate;
+ (instancetype)channelFromKick:(NSDictionary *)channel;
- (NSString *)nameForDisplay;
- (BOOL)isLive;
@end

@interface KCVideo : NSObject
@property (nonatomic, copy) NSString *videoId;          // the recording's uuid
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *previewURL;
@property (nonatomic, copy) NSString *categoryName;
@property (nonatomic, copy) NSString *sourceURL;        // the recording's HLS master
@property (nonatomic, copy) NSString *ownerSlug;
@property (nonatomic, copy) NSString *ownerName;
@property (nonatomic, copy) NSString *channelId;        // whose chat history replays beside it
@property (nonatomic, copy) NSString *cursor;
@property (nonatomic, strong) NSDate *publishedAt;      // when the broadcast began (the replay's clock)
@property (nonatomic) NSTimeInterval length;
@property (nonatomic) NSInteger views;
// An entry of channels/<slug>/videos; the channel fills in the owner when the entry does not carry it
+ (instancetype)videoFromKick:(NSDictionary *)item owner:(KCChannel *)owner;
@end

@interface KCClip : NSObject
@property (nonatomic, copy) NSString *clipId;           // "clip_01H8..."
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *thumbnailURL;
@property (nonatomic, copy) NSString *curatorName;      // who made the clip
@property (nonatomic, copy) NSString *categoryName;
@property (nonatomic, copy) NSString *broadcasterSlug;
@property (nonatomic, copy) NSString *broadcasterName;
@property (nonatomic, copy) NSString *playlistURL;      // HLS (a media playlist with byte ranges)
@property (nonatomic, copy) NSString *cursor;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic) NSTimeInterval duration;
@property (nonatomic) NSInteger views;
+ (instancetype)clipFromKick:(NSDictionary *)item;
@end

// The picture of a {src, srcset} / {url, responsive} object (or a plain string), the smallest at least `width` wide
NSString *KCImageURL(id node, NSInteger width);
// "url 1920w, url 1280w" -> NSNumber width -> URL
NSDictionary *KCParseSrcset(NSString *srcset);
