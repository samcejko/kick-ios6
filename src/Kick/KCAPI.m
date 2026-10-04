#import "KCAPI.h"
#import "KCChatMessage.h"
#import "KCSettings.h"
#import "KCUtils.h"
#import "KCCommon.h"

#include <math.h>
#include <time.h>

NSString * const KCClipPeriodDay   = @"day";
NSString * const KCClipPeriodWeek  = @"week";
NSString * const KCClipPeriodMonth = @"month";
NSString * const KCClipPeriodAll   = @"all";

static NSString * const KCSiteBase = @"https://kick.com";
static const NSInteger KCPageSize = 24;
static const NSInteger KCFilterPageLimit = 5;      // pages fetched in one go to fill a filtered list
static const NSUInteger KCParallelChannels = 6;

@implementation KCAPI

+ (NSDictionary *)headers
{
    // (the API answers anyone; a browser-like agent keeps the bot protection in front of it quiet)
    return @{ @"Accept": @"application/json",
              @"User-Agent": @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15" };
}

+ (NSError *)errorFor:(NSError *)error json:(id)json
{
    NSString *message = KCStr(KCDict(json)[@"message"]);
    if (error.code == 404) return KCMakeError(404, L(@"Nothing was found at this address."));
    if (message.length && error.code >= 400) return KCMakeError(error.code, message);
    return error;
}

+ (KCHTTPTask *)get:(NSString *)path completion:(void (^)(id json, NSError *error))completion
{
    NSString *url = [path hasPrefix:@"http"] ? path : [KCSiteBase stringByAppendingString:path];
    return [KCHTTP getJSON:url headers:[self headers] completion:^(id json, NSInteger status, NSError *error) {
        if (error) { completion(json, [self errorFor:error json:json]); return; }
        completion(json, nil);
    }];
}

#pragma mark - Language filter

+ (NSString *)kickLanguageNameForCode:(NSString *)code
{
    static NSDictionary *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{ @"cs": @"Czech", @"sk": @"Slovak", @"en": @"English", @"es": @"Spanish", @"de": @"German", @"fr": @"French",
                   @"it": @"Italian", @"pl": @"Polish", @"pt": @"Portuguese", @"ru": @"Russian", @"uk": @"Ukrainian", @"tr": @"Turkish",
                   @"ar": @"Arabic", @"ja": @"Japanese", @"ko": @"Korean", @"zh": @"Chinese", @"nl": @"Dutch", @"sv": @"Swedish",
                   @"no": @"Norwegian", @"da": @"Danish", @"fi": @"Finnish", @"hu": @"Hungarian", @"ro": @"Romanian", @"el": @"Greek",
                   @"bg": @"Bulgarian", @"th": @"Thai", @"vi": @"Vietnamese", @"id": @"Indonesian", @"hi": @"Hindi", @"he": @"Hebrew" };
    });
    return names[[code lowercaseString]];
}

+ (BOOL)streamMatchesLanguageFilter:(KCStream *)stream
{
    NSString *code = [KCSettings streamLanguage];
    if (!code.length) return YES;
    NSString *name = [self kickLanguageNameForCode:code];
    if (!name.length) return YES;   // (a language Kick does not name: no filter rather than an empty list)
    return [stream.language hasPrefix:name];   // "English (India)" counts as English
}

#pragma mark - Paged stream lists

// Pages of the live directory; with a language filter, pages are fetched until something matches (or there are no
// more), so a filtered list does not come back empty while further pages would have had streams
+ (KCHTTPTask *)streamPagesAt:(NSInteger)page query:(NSString *)query completion:(KCListCompletion)completion
{
    KCHTTPTask *outer = [[KCHTTPTask alloc] init];
    __block KCHTTPTask *inner = nil;
    __block void (^fetch)(NSInteger) = nil;
    outer.cancelBlock = ^{ [inner cancel]; fetch = nil; };
    NSMutableArray *gathered = [NSMutableArray array];
    __block NSInteger fetched = 0;
    fetch = ^(NSInteger p) {
        NSString *path = [NSString stringWithFormat:@"/stream/livestreams/en?page=%ld&limit=%ld&sort=desc%@", (long)p, (long)KCPageSize, query ?: @""];
        inner = [self get:path completion:^(id json, NSError *error) {
            if (outer.isCancelled) { fetch = nil; return; }
            if (error) { completion(gathered.count ? gathered : nil, nil, gathered.count ? nil : error); fetch = nil; return; }
            NSDictionary *d = KCDict(json);
            for (id item in KCArr(d[@"data"])) {
                KCStream *s = [KCStream streamFromKick:item];
                if (s && [self streamMatchesLanguageFilter:s]) [gathered addObject:s];
            }
            fetched++;
            BOOL more = [KCStr(d[@"next_page_url"]) length] > 0;
            NSString *next = more ? [NSString stringWithFormat:@"%ld", (long)(p + 1)] : nil;
            if (!gathered.count && more && fetched < KCFilterPageLimit) { fetch(p + 1); return; }
            completion(gathered, next, nil);
            fetch = nil;
        }];
    };
    fetch(page);
    return outer;
}

+ (KCHTTPTask *)topStreamsAfter:(NSString *)cursor completion:(KCListCompletion)completion
{
    return [self streamPagesAt:MAX(1, [cursor integerValue]) query:nil completion:completion];
}

+ (KCHTTPTask *)streamsForCategory:(KCCategory *)category after:(NSString *)cursor completion:(KCListCompletion)completion
{
    NSString *query = [@"&subcategory=" stringByAppendingString:[KCUtils urlEncode:category.slug ?: @""]];
    return [self streamPagesAt:MAX(1, [cursor integerValue]) query:query completion:completion];
}

+ (KCHTTPTask *)topCategoriesAfter:(NSString *)cursor completion:(KCListCompletion)completion
{
    NSInteger page = MAX(1, [cursor integerValue]);
    NSString *path = [NSString stringWithFormat:@"/api/v1/subcategories?limit=%ld&page=%ld", (long)KCPageSize, (long)page];
    return [self get:path completion:^(id json, NSError *error) {
        if (error) { completion(nil, nil, error); return; }
        NSDictionary *d = KCDict(json);
        NSMutableArray *items = [NSMutableArray array];
        for (id node in KCArr(d[@"data"])) {
            KCCategory *c = [KCCategory categoryFromKick:node];
            if (c) [items addObject:c];
        }
        BOOL more = [KCStr(d[@"next_page_url"]) length] > 0;
        completion(items, more ? [NSString stringWithFormat:@"%ld", (long)(page + 1)] : nil, nil);
    }];
}

+ (KCHTTPTask *)category:(NSString *)slug completion:(void (^)(KCCategory *, NSError *))completion
{
    NSString *path = [@"/api/v1/subcategories/" stringByAppendingString:[KCUtils urlEncode:slug ?: @""]];
    return [self get:path completion:^(id json, NSError *error) {
        KCCategory *c = error ? nil : [KCCategory categoryFromKick:json];
        completion(c, c ? nil : (error ?: KCMakeError(KCErrorBadResponse, L(@"Nothing was found at this address."))));
    }];
}

#pragma mark - Search

+ (KCHTTPTask *)search:(NSString *)text completion:(void (^)(NSArray *, NSArray *, NSError *))completion
{
    NSString *path = [@"/api/search?searched_word=" stringByAppendingString:[KCUtils urlEncode:text ?: @""]];
    return [self get:path completion:^(id json, NSError *error) {
        if (error) { completion(nil, nil, error); return; }
        NSDictionary *d = KCDict(json);
        NSMutableArray *channels = [NSMutableArray array], *categories = [NSMutableArray array];
        for (id node in KCArr(d[@"channels"])) {
            KCChannel *c = [KCChannel channelFromKick:node];
            if (c) [channels addObject:c];
        }
        for (id node in KCArr(d[@"categories"])) {
            KCCategory *c = [KCCategory categoryFromKick:node];
            if (c) [categories addObject:c];
        }
        completion(channels, categories, nil);
    }];
}

#pragma mark - Channels

+ (KCHTTPTask *)channel:(NSString *)slug completion:(void (^)(KCChannel *, NSError *))completion
{
    NSString *path = [@"/api/v2/channels/" stringByAppendingString:[KCUtils urlEncode:[slug lowercaseString] ?: @""]];
    return [self get:path completion:^(id json, NSError *error) {
        KCChannel *c = error ? nil : [KCChannel channelFromKick:json];
        if (!c && !error) error = KCMakeError(KCErrorBadResponse, L(@"This channel does not exist."));
        completion(c, error);
    }];
}

+ (KCHTTPTask *)channels:(NSArray *)slugs completion:(void (^)(NSArray *, NSError *))completion
{
    KCHTTPTask *outer = [[KCHTTPTask alloc] init];
    if (!slugs.count) { KCMain(^{ completion(@[], nil); }); return outer; }
    NSMutableArray *results = [NSMutableArray arrayWithCapacity:slugs.count];
    for (NSUInteger i = 0; i < slugs.count; i++) [results addObject:[NSNull null]];
    NSMutableArray *tasks = [NSMutableArray array];
    __block NSUInteger next = 0, running = 0, done = 0;
    __block NSError *failure = nil;
    __block void (^startMore)(void);
    startMore = ^{
        while (running < KCParallelChannels && next < slugs.count) {
            NSUInteger index = next++;
            running++;
            KCHTTPTask *t = [self channel:slugs[index] completion:^(KCChannel *channel, NSError *error) {
                if (outer.isCancelled) { startMore = nil; return; }
                running--;
                done++;
                if (channel) results[index] = channel;
                else if (error && error.code != 404) failure = error;
                if (done == slugs.count) {
                    NSMutableArray *found = [NSMutableArray array];
                    for (id r in results) if ([r isKindOfClass:[KCChannel class]]) [found addObject:r];
                    completion(found, found.count ? nil : failure);
                    startMore = nil;
                    return;
                }
                if (startMore) startMore();
            }];
            if (t) [tasks addObject:t];
        }
    };
    outer.cancelBlock = ^{ for (KCHTTPTask *t in tasks) [t cancel]; startMore = nil; };
    startMore();
    return outer;
}

+ (KCHTTPTask *)videosForChannel:(NSString *)slug after:(NSString *)cursor completion:(KCListCompletion)completion
{
    NSString *s = [slug lowercaseString] ?: @"";
    NSString *path = [NSString stringWithFormat:@"/api/v2/channels/%@/videos", [KCUtils urlEncode:s]];
    return [self get:path completion:^(id json, NSError *error) {
        if (error) { completion(nil, nil, error); return; }
        KCChannel *owner = [[KCChannel alloc] init];
        owner.slug = s;
        NSMutableArray *items = [NSMutableArray array];
        for (id item in KCArr(json)) {
            KCVideo *v = [KCVideo videoFromKick:item owner:owner];
            if (v) [items addObject:v];
        }
        completion(items, nil, nil);   // (Kick hands over every recording at once)
    }];
}

+ (KCHTTPTask *)clipsForChannel:(NSString *)slug period:(NSString *)period after:(NSString *)cursor completion:(KCListCompletion)completion
{
    NSString *base = [NSString stringWithFormat:@"/api/v2/channels/%@/clips", [KCUtils urlEncode:[slug lowercaseString] ?: @""]];
    return [self clipsAt:base period:period after:cursor completion:completion];
}

+ (KCHTTPTask *)clipsForCategory:(KCCategory *)category period:(NSString *)period after:(NSString *)cursor completion:(KCListCompletion)completion
{
    NSString *base = [NSString stringWithFormat:@"/api/v2/categories/%@/clips", [KCUtils urlEncode:category.slug ?: @""]];
    return [self clipsAt:base period:period after:cursor completion:completion];
}

// The most watched clips of a channel or a category in a period, a page of twenty
+ (KCHTTPTask *)clipsAt:(NSString *)base period:(NSString *)period after:(NSString *)cursor completion:(KCListCompletion)completion
{
    NSMutableString *path = [NSMutableString stringWithFormat:@"%@?sort=view&time=%@", base, period.length ? period : KCClipPeriodAll];
    if (cursor.length) [path appendFormat:@"&cursor=%@", [KCUtils urlEncode:cursor]];
    return [self get:path completion:^(id json, NSError *error) {
        if (error) { completion(cursor.length ? @[] : nil, nil, cursor.length ? nil : error); return; }
        NSDictionary *d = KCDict(json);
        NSMutableArray *items = [NSMutableArray array];
        for (id item in KCArr(d[@"clips"])) {
            KCClip *c = [KCClip clipFromKick:item];
            if (c) [items addObject:c];
        }
        // (the next page's cursor: a clip id, or for a channel the JSON text of {view, id}; it goes back as it came)
        id nextCursor = d[@"nextCursor"];
        NSString *next = nil;
        if ([nextCursor isKindOfClass:[NSDictionary class]]) {
            NSData *data = [KCUtils JSONDataFromObject:nextCursor];
            next = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        } else {
            next = KCStr(nextCursor);
        }
        completion(items, items.count && next.length ? next : nil, nil);
    }];
}

#pragma mark - Chat

+ (KCHTTPTask *)recentMessagesForChannelId:(NSString *)channelId completion:(void (^)(NSArray *, NSError *))completion
{
    NSString *path = [NSString stringWithFormat:@"/api/v2/channels/%@/messages", [KCUtils urlEncode:channelId ?: @""]];
    return [self get:path completion:^(id json, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSMutableArray *messages = [NSMutableArray array];
        // (the newest come first)
        for (id m in [[KCArr(KCDict(KCDict(json)[@"data"])[@"messages"]) reverseObjectEnumerator] allObjects]) {
            KCChatMessage *message = [KCChatMessage messageFromKick:m];
            if (message) [messages addObject:message];
        }
        completion(messages, nil);
    }];
}

+ (KCHTTPTask *)chatReplayForChannelId:(NSString *)channelId at:(NSDate *)time completion:(void (^)(NSArray *, NSError *))completion
{
    // the history from a moment on: Kick answers with the messages of the next five seconds
    char stamp[32];
    time_t seconds = (time_t)floor([time timeIntervalSince1970]);
    struct tm t;
    gmtime_r(&seconds, &t);
    strftime(stamp, sizeof(stamp), "%Y-%m-%dT%H:%M:%S.000Z", &t);
    NSString *path = [NSString stringWithFormat:@"/api/v2/channels/%@/messages?start_time=%@", [KCUtils urlEncode:channelId ?: @""],
                      [KCUtils urlEncode:[NSString stringWithUTF8String:stamp]]];
    return [self get:path completion:^(id json, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSMutableArray *messages = [NSMutableArray array];
        for (id m in KCArr(KCDict(KCDict(json)[@"data"])[@"messages"])) {
            KCChatMessage *message = [KCChatMessage messageFromKick:m];
            if (message) [messages addObject:message];
        }
        [messages sortUsingComparator:^NSComparisonResult(KCChatMessage *a, KCChatMessage *b) { return [a.timestamp compare:b.timestamp]; }];
        completion(messages, nil);
    }];
}

@end
