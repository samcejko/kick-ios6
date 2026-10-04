#import "KCEmotes.h"
#import "KCHTTP.h"
#import "KCSettings.h"
#import "KCUtils.h"
#import "KCCommon.h"

NSString * const KCEmotesDidChangeNotification = @"KCEmotesDidChangeNotification";

@implementation KCEmote

- (NSString *)urlForScale:(CGFloat)scale
{
    if (scale > 1.5 && self.url2x.length) return self.url2x;
    return self.url1x;
}

- (NSString *)providerName
{
    return self.provider == KCEmoteProvider7TV ? @"7TV" : @"Kick";
}

@end

@interface KCEmoteStore ()
@property (nonatomic, strong) NSMutableDictionary *globalEmotes;      // name -> KCEmote
@property (nonatomic, strong) NSMutableDictionary *channelEmotes;     // name -> KCEmote
@property (nonatomic, copy) NSString *channelId;
@property (nonatomic) BOOL globalsLoading;
@property (nonatomic, strong) NSDate *globalsLoadedAt;
@property (nonatomic, strong) KCHTTPTask *channelTask;
@end

@implementation KCEmoteStore

+ (instancetype)shared
{
    static KCEmoteStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [[KCEmoteStore alloc] init]; });
    return store;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _globalEmotes = [NSMutableDictionary dictionary];
        _channelEmotes = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)changed
{
    [[NSNotificationCenter defaultCenter] postNotificationName:KCEmotesDidChangeNotification object:self];
}

#pragma mark - Lookups (any thread)

- (KCEmote *)thirdPartyEmoteNamed:(NSString *)word channelId:(NSString *)channelId
{
    if (!word.length) return nil;
    @synchronized (self) {
        KCEmote *e = nil;
        if (channelId.length && [channelId isEqualToString:self.channelId]) e = self.channelEmotes[word];
        return e ?: self.globalEmotes[word];
    }
}

+ (KCEmote *)kickEmoteWithId:(NSString *)emoteId name:(NSString *)name animated:(BOOL)animated
{
    if (!emoteId.length) return nil;
    KCEmote *e = [[KCEmote alloc] init];
    e.provider = KCEmoteProviderKick;
    e.emoteId = emoteId;
    e.name = name ?: emoteId;
    e.width = 28;
    e.height = 28;
    e.animated = animated;
    // (one size, a GIF - animated or still - at twice the 1x size, so it serves both screens)
    e.url1x = [NSString stringWithFormat:@"https://files.kick.com/emotes/%@/fullsize", emoteId];
    e.url2x = e.url1x;
    return e;
}

#pragma mark - 7TV

- (NSInteger)dimension:(id)value fallback:(NSInteger)fallback
{
    NSInteger v = KCInt(value);
    return v > 0 && v < 400 ? v : fallback;
}

// 7TV: emotes: [ { name, flags, data: { animated, host: { url, files: [ {name, width, height, format} ] } } } ]
- (NSArray *)emotesFrom7TV:(NSArray *)list
{
    NSMutableArray *result = [NSMutableArray array];
    for (id item in list) {
        NSDictionary *d = KCDict(item);
        NSString *name = KCStr(d[@"name"]);
        NSDictionary *data = KCDict(d[@"data"]);
        NSDictionary *host = KCDict(data[@"host"]);
        NSString *base = KCStr(host[@"url"]);
        if (!name.length || !base.length) continue;
        if ([base hasPrefix:@"//"]) base = [@"https:" stringByAppendingString:base];
        BOOL animated = KCBool(data[@"animated"]);
        // the GIF of an animated emote, the PNG of a still one (AVIF cannot be decoded here)
        NSString *wanted = animated ? @"GIF" : @"PNG";
        NSDictionary *file1 = nil, *file2 = nil;
        for (id f in KCArr(host[@"files"])) {
            NSDictionary *file = KCDict(f);
            if (![[KCStr(file[@"format"]) uppercaseString] isEqualToString:wanted]) continue;
            NSString *fileName = KCStr(file[@"name"]);
            if ([fileName hasPrefix:@"1x"]) file1 = file;
            else if ([fileName hasPrefix:@"2x"]) file2 = file;
        }
        if (!file1) continue;
        KCEmote *e = [[KCEmote alloc] init];
        e.provider = KCEmoteProvider7TV;
        e.emoteId = KCStr(d[@"id"]) ?: name;
        e.name = name;
        e.animated = animated;
        e.zeroWidth = (KCInt(d[@"flags"]) & 1) != 0;
        e.width = [self dimension:file1[@"width"] fallback:32];
        e.height = [self dimension:file1[@"height"] fallback:32];
        e.url1x = [NSString stringWithFormat:@"%@/%@", base, KCStr(file1[@"name"])];
        if (file2) e.url2x = [NSString stringWithFormat:@"%@/%@", base, KCStr(file2[@"name"])];
        [result addObject:e];
    }
    return result;
}

- (void)addEmotes:(NSArray *)emotes toChannel:(BOOL)channel
{
    if (!emotes.count) return;
    @synchronized (self) {
        NSMutableDictionary *map = channel ? self.channelEmotes : self.globalEmotes;
        for (KCEmote *e in emotes) map[e.name] = e;
    }
    [self changed];
}

#pragma mark - Loading

- (void)loadGlobalsIfNeeded
{
    if (![KCSettings thirdPartyEmotes] || self.globalsLoading) return;
    if (self.globalsLoadedAt && -[self.globalsLoadedAt timeIntervalSinceNow] < 6 * 3600) return;
    self.globalsLoading = YES;
    [KCHTTP getJSON:@"https://7tv.io/v3/emote-sets/global" headers:nil completion:^(id json, NSInteger status, NSError *error) {
        self.globalsLoading = NO;
        NSArray *emotes = [self emotesFrom7TV:KCArr(KCDict(json)[@"emotes"])];
        if (emotes.count) {
            self.globalsLoadedAt = [NSDate date];
            [self addEmotes:emotes toChannel:NO];
        }
    }];
}

- (void)loadChannel:(NSString *)channelId account:(NSString *)accountId
{
    if (!channelId.length) return;
    if ([channelId isEqualToString:self.channelId]) return;
    [self.channelTask cancel];
    self.channelTask = nil;
    @synchronized (self) {
        self.channelId = channelId;
        [self.channelEmotes removeAllObjects];
    }
    [self changed];
    [self loadGlobalsIfNeeded];
    if (![KCSettings thirdPartyEmotes] || !accountId.length) return;
    // 7TV knows Kick channels by the owner's Kick user id
    NSString *url = [@"https://7tv.io/v3/users/kick/" stringByAppendingString:[KCUtils urlEncode:accountId]];
    self.channelTask = [KCHTTP getJSON:url headers:nil completion:^(id json, NSInteger status, NSError *error) {
        if (![channelId isEqualToString:self.channelId]) return;
        [self addEmotes:[self emotesFrom7TV:KCArr(KCDict(KCDict(json)[@"emote_set"])[@"emotes"])] toChannel:YES];
    }];
}

@end
