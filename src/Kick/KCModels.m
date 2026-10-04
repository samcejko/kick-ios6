#import "KCModels.h"
#import "KCCommon.h"

#pragma mark - Pictures

NSDictionary *KCParseSrcset(NSString *srcset)
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (![srcset isKindOfClass:[NSString class]]) return result;
    for (NSString *entry in [srcset componentsSeparatedByString:@","]) {
        NSString *e = [entry stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSRange space = [e rangeOfString:@" " options:NSBackwardsSearch];
        if (space.location == NSNotFound) continue;
        NSString *url = [e substringToIndex:space.location];
        NSString *descriptor = [e substringFromIndex:space.location + 1];
        if (![descriptor hasSuffix:@"w"]) continue;
        NSInteger width = [descriptor integerValue];
        if (width > 0 && url.length) result[@(width)] = url;
    }
    return result;
}

static NSString *KCPickWidth(NSDictionary *byWidth, NSInteger width)
{
    if (!byWidth.count) return nil;
    NSArray *widths = [[byWidth allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber *w in widths) {
        if (w.integerValue >= width) return byWidth[w];
    }
    return byWidth[[widths lastObject]];   // (none that wide: the largest there is)
}

NSString *KCImageURL(id node, NSInteger width)
{
    if ([node isKindOfClass:[NSString class]]) return [node length] ? node : nil;
    NSDictionary *d = KCDict(node);
    if (!d) return nil;
    NSString *picked = KCPickWidth(KCParseSrcset(KCStr(d[@"srcset"])), width);
    if (picked.length) return picked;
    NSString *plain = KCStr(d[@"src"]) ?: KCStr(d[@"url"]);
    return plain.length ? plain : nil;
}

// The profile picture of a user object - the key differs between Kick's endpoints
static NSString *KCAvatar(NSDictionary *user)
{
    NSString *url = KCStr(user[@"profilepic"]) ?: (KCStr(user[@"profile_pic"]) ?: KCStr(user[@"profilePic"]));
    return url.length ? url : nil;
}

static NSArray *KCTagNames(id value)
{
    NSMutableArray *names = [NSMutableArray array];
    for (id t in KCArr(value)) {
        NSString *name = KCStr(t) ?: KCStr(KCDict(t)[@"name"]);
        if (name.length) [names addObject:name];
    }
    return names;
}

static NSString *KCNameForDisplay(NSString *displayName, NSString *slug)
{
    if (!displayName.length) return slug ?: @"";
    if (!slug.length || [[displayName lowercaseString] isEqualToString:[slug lowercaseString]]) return displayName;
    return [NSString stringWithFormat:@"%@ (%@)", displayName, slug];
}

#pragma mark - Stream

@implementation KCStream

- (void)fillFromLivestream:(NSDictionary *)live
{
    NSDictionary *category = KCDict([KCArr(live[@"categories"]) firstObject]);
    self.categoryId = KCStr(category[@"id"]);
    self.categoryName = KCStr(category[@"name"]);
    self.categorySlug = KCStr(category[@"slug"]);
    self.language = KCStr(live[@"language"]);
    self.tags = KCTagNames(live[@"tags"]);
    NSDictionary *thumb = KCDict(live[@"thumbnail"]);
    NSMutableDictionary *thumbs = [KCParseSrcset(KCStr(thumb[@"srcset"])) mutableCopy];
    NSString *single = KCStr(thumb[@"src"]) ?: KCStr(thumb[@"url"]);
    if (!thumbs.count && single.length) thumbs[@(1280)] = single;
    self.thumbnails = thumbs;
    self.startedAt = KCDateFromISO(KCStr(live[@"start_time"]) ?: KCStr(live[@"created_at"]));
    self.viewers = KCInt(live[@"viewer_count"]) ?: KCInt(live[@"viewers"]);
    self.isMature = KCBool(live[@"is_mature"]);
}

+ (instancetype)streamFromKick:(NSDictionary *)item
{
    item = KCDict(item);
    if (!item) return nil;
    NSDictionary *channel = KCDict(item[@"channel"]);
    NSDictionary *user = KCDict(channel[@"user"]);
    KCStream *s = [[KCStream alloc] init];
    s.streamId = KCStr(item[@"id"]);
    s.title = KCStr(item[@"session_title"]);
    s.slug = [KCStr(channel[@"slug"]) lowercaseString];
    s.displayName = KCStr(user[@"username"]) ?: KCStr(channel[@"slug"]);
    s.userId = KCStr(channel[@"id"]) ?: KCStr(item[@"channel_id"]);
    s.avatarURL = KCAvatar(user);
    [s fillFromLivestream:item];
    return s.slug.length ? s : nil;
}

+ (instancetype)streamFromLivestream:(NSDictionary *)live channel:(NSDictionary *)channel
{
    live = KCDict(live);
    channel = KCDict(channel);
    if (!live || !channel) return nil;
    NSDictionary *user = KCDict(channel[@"user"]);
    KCStream *s = [[KCStream alloc] init];
    s.streamId = KCStr(live[@"id"]);
    s.title = KCStr(live[@"session_title"]);
    s.slug = [KCStr(channel[@"slug"]) lowercaseString];
    s.displayName = KCStr(user[@"username"]) ?: KCStr(channel[@"slug"]);
    s.userId = KCStr(channel[@"id"]);
    s.avatarURL = KCAvatar(user);
    [s fillFromLivestream:live];
    return s.slug.length ? s : nil;
}

- (NSString *)nameForDisplay
{
    return KCNameForDisplay(self.displayName, self.slug);
}

- (NSString *)previewURLWithWidth:(NSInteger)width height:(NSInteger)height
{
    return KCPickWidth(self.thumbnails, width);
}

@end

#pragma mark - Category

@implementation KCCategory

+ (instancetype)categoryFromKick:(NSDictionary *)node
{
    node = KCDict(node);
    if (!node) return nil;
    KCCategory *c = [[KCCategory alloc] init];
    c.categoryId = KCStr(node[@"id"]);
    c.slug = KCStr(node[@"slug"]);
    c.name = KCStr(node[@"name"]);
    c.imageURL = KCImageURL(node[@"banner"], 300) ?: KCImageURL(node[@"image"], 300);
    c.parentName = KCStr(KCDict(node[@"category"])[@"name"]);
    c.viewers = KCInt(node[@"viewers"]);
    c.followers = KCInt(node[@"followers_count"]);
    return c.slug.length ? c : nil;
}

- (NSString *)title
{
    return self.name.length ? self.name : (self.slug ?: @"");
}

@end

#pragma mark - Channel

@implementation KCChannel

+ (instancetype)channelFromKick:(NSDictionary *)ch
{
    ch = KCDict(ch);
    if (!ch) return nil;
    NSDictionary *user = KCDict(ch[@"user"]);
    KCChannel *c = [[KCChannel alloc] init];
    c.userId = KCStr(ch[@"id"]);
    c.accountId = KCStr(ch[@"user_id"]) ?: KCStr(ch[@"userId"]);
    c.slug = [KCStr(ch[@"slug"]) lowercaseString];
    c.displayName = KCStr(user[@"username"]) ?: c.slug;
    c.bio = KCStr(user[@"bio"]);
    c.avatarURL = KCAvatar(user);
    c.bannerURL = KCImageURL(ch[@"banner_image"], 1200);
    c.offlineImageURL = KCImageURL(ch[@"offline_banner_image"], 1200);
    c.chatroomId = KCStr(KCDict(ch[@"chatroom"])[@"id"]);
    c.playbackURL = KCStr(ch[@"playback_url"]);
    c.followers = KCInt(ch[@"followers_count"]) ?: KCInt(ch[@"followersCount"]);
    id verified = ch[@"verified"];
    c.isVerified = [verified isKindOfClass:[NSDictionary class]] || KCBool(verified);
    c.isAffiliate = KCBool(ch[@"is_affiliate"]);
    NSDictionary *recent = KCDict([(KCArr(ch[@"recent_categories"]) ?: KCArr(ch[@"recentCategories"])) firstObject]);
    c.lastCategoryName = KCStr(recent[@"name"]);
    NSDictionary *live = KCDict(ch[@"livestream"]);
    if (live && (!live[@"is_live"] || KCBool(live[@"is_live"]))) {
        c.stream = [KCStream streamFromLivestream:live channel:ch];
    } else if (KCBool(ch[@"isLive"])) {
        // (search results only say that the channel is live)
        KCStream *s = [[KCStream alloc] init];
        s.slug = c.slug;
        s.displayName = c.displayName;
        s.userId = c.userId;
        s.avatarURL = c.avatarURL;
        c.stream = s;
    }
    return c.slug.length ? c : nil;
}

- (NSString *)nameForDisplay
{
    return KCNameForDisplay(self.displayName, self.slug);
}

- (BOOL)isLive
{
    return self.stream != nil;
}

@end

#pragma mark - Video

@implementation KCVideo

+ (instancetype)videoFromKick:(NSDictionary *)item owner:(KCChannel *)owner
{
    item = KCDict(item);
    if (!item) return nil;
    NSDictionary *video = KCDict(item[@"video"]);
    NSDictionary *channel = KCDict(item[@"channel"]);
    KCVideo *v = [[KCVideo alloc] init];
    v.videoId = KCStr(video[@"uuid"]) ?: KCStr(item[@"id"]);
    v.title = KCStr(item[@"session_title"]);
    v.previewURL = KCImageURL(item[@"thumbnail"], 640) ?: KCStr(video[@"thumb"]);
    v.categoryName = KCStr(KCDict([KCArr(item[@"categories"]) firstObject])[@"name"]);
    v.sourceURL = KCStr(item[@"source"]);
    v.ownerSlug = [KCStr(channel[@"slug"]) lowercaseString] ?: owner.slug;
    v.ownerName = KCStr(KCDict(channel[@"user"])[@"username"]) ?: owner.displayName;
    v.channelId = KCStr(item[@"channel_id"]) ?: (KCStr(channel[@"id"]) ?: owner.userId);
    v.publishedAt = KCDateFromISO(KCStr(item[@"start_time"]) ?: KCStr(item[@"created_at"]));
    double milliseconds = KCDbl(item[@"duration"]);
    v.length = milliseconds > 0 ? milliseconds / 1000.0 : 0;
    v.views = KCInt(item[@"views"]) ?: KCInt(video[@"views"]);
    return v.sourceURL.length ? v : nil;
}

@end

#pragma mark - Clip

@implementation KCClip

+ (instancetype)clipFromKick:(NSDictionary *)item
{
    item = KCDict(item);
    if (!item) return nil;
    NSDictionary *channel = KCDict(item[@"channel"]);
    KCClip *c = [[KCClip alloc] init];
    c.clipId = KCStr(item[@"id"]);
    c.title = KCStr(item[@"title"]);
    c.thumbnailURL = KCStr(item[@"thumbnail_url"]);
    c.curatorName = KCStr(KCDict(item[@"creator"])[@"username"]);
    c.categoryName = KCStr(KCDict(item[@"category"])[@"name"]);
    c.broadcasterSlug = [KCStr(channel[@"slug"]) lowercaseString];
    c.broadcasterName = KCStr(channel[@"username"]) ?: (KCStr(KCDict(channel[@"user"])[@"username"]) ?: c.broadcasterSlug);
    c.playlistURL = KCStr(item[@"clip_url"]) ?: KCStr(item[@"video_url"]);
    c.createdAt = KCDateFromISO(KCStr(item[@"created_at"]));
    c.duration = KCDbl(item[@"duration"]);
    c.views = KCInt(item[@"views"]) ?: KCInt(item[@"view_count"]);
    return (c.clipId.length && c.playlistURL.length) ? c : nil;
}

@end
