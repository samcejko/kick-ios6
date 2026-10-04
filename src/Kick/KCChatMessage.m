#import "KCChatMessage.h"
#import "KCUtils.h"
#import "KCCommon.h"

// Leaves out the emoji this system cannot draw; the emote positions move along with the text
static void KCCleanMessageText(KCChatMessage *m)
{
    m.systemText = [KCUtils displayText:m.systemText];
    m.replyParentText = [KCUtils displayText:m.replyParentText];
    NSMutableArray *dropped = [NSMutableArray array];
    NSString *clean = [KCUtils displayText:m.text dropped:dropped];
    if (!dropped.count) return;
    for (KCChatEmoteRange *r in m.emotes) {
        NSUInteger shift = 0;
        for (NSValue *v in dropped) {
            NSRange d = [v rangeValue];
            if (d.location < r.range.location) shift += d.length;
        }
        r.range = NSMakeRange(r.range.location - MIN(shift, r.range.location), r.range.length);
    }
    m.text = clean;
}

// "Hi [emote:37226:KEKW] there" -> "Hi KEKW there" with an emote range over "KEKW" (emotes may be nil: names only)
static NSString *KCTextWithKickEmotes(NSString *raw, NSMutableArray *emotes)
{
    if (!raw.length || [raw rangeOfString:@"[emote:"].location == NSNotFound) return raw ?: @"";
    static NSRegularExpression *pattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ pattern = [NSRegularExpression regularExpressionWithPattern:@"\\[emote:(\\d+):([^\\]]*)\\]" options:0 error:NULL]; });
    NSMutableString *out = [NSMutableString stringWithCapacity:raw.length];
    __block NSUInteger last = 0;
    [pattern enumerateMatchesInString:raw options:0 range:NSMakeRange(0, raw.length) usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        if (match.range.location > last) [out appendString:[raw substringWithRange:NSMakeRange(last, match.range.location - last)]];
        NSString *emoteId = [raw substringWithRange:[match rangeAtIndex:1]];
        NSString *name = [raw substringWithRange:[match rangeAtIndex:2]];
        if (!name.length) name = @"emote";
        KCChatEmoteRange *r = [[KCChatEmoteRange alloc] init];
        r.emoteId = emoteId;
        r.range = NSMakeRange(out.length, name.length);
        [emotes addObject:r];
        [out appendString:name];
        last = NSMaxRange(match.range);
    }];
    if (last < raw.length) [out appendString:[raw substringFromIndex:last]];
    return out;
}

// metadata comes as an object over the WebSocket and as JSON text in the history
static NSDictionary *KCMetadata(id value)
{
    if ([value isKindOfClass:[NSDictionary class]]) return value;
    if ([value isKindOfClass:[NSString class]]) return KCDict([KCUtils JSONObjectFromData:[value dataUsingEncoding:NSUTF8StringEncoding]]);
    return nil;
}

@implementation KCChatEmoteRange
@end

@implementation KCChatMessage

- (instancetype)init
{
    self = [super init];
    if (self) _replayOffset = -1;
    return self;
}

+ (instancetype)messageFromKick:(NSDictionary *)data
{
    data = KCDict(data);
    if (!data) return nil;
    NSDictionary *sender = KCDict(data[@"sender"]);
    NSDictionary *identity = KCDict(sender[@"identity"]);
    KCChatMessage *m = [[KCChatMessage alloc] init];
    m.kind = KCChatKindMessage;
    m.messageId = KCStr(data[@"id"]);
    m.slug = [(KCStr(sender[@"slug"]) ?: KCStr(sender[@"username"])) lowercaseString];
    m.displayName = KCStr(sender[@"username"]) ?: m.slug;
    m.userId = KCStr(sender[@"id"]) ?: KCStr(data[@"user_id"]);
    NSString *color = KCStr(identity[@"color"]);
    m.colorHex = color.length ? color : nil;
    m.timestamp = KCDateFromISO(KCStr(data[@"created_at"])) ?: [NSDate date];
    // the badges with pictures (badges_v2); the older list only names them
    NSMutableArray *badges = [NSMutableArray array];
    for (id b in KCArr(identity[@"badges_v2"])) {
        NSDictionary *d = KCDict(b);
        NSString *url = KCStr(d[@"image_url"]);
        if (url.length) [badges addObject:@[ KCStr(d[@"name"]) ?: @"", url ]];
    }
    m.badges = badges;
    NSMutableArray *emotes = [NSMutableArray array];
    m.text = KCTextWithKickEmotes(KCStr(data[@"content"]) ?: @"", emotes);
    m.emotes = emotes;
    // a reply quotes the message it answers
    if ([KCStr(data[@"type"]) isEqualToString:@"reply"]) {
        NSDictionary *metadata = KCMetadata(data[@"metadata"]);
        NSString *parent = KCStr(KCDict(metadata[@"original_sender"])[@"username"]);
        if (parent.length) {
            m.replyParentName = parent;
            m.replyParentText = KCTextWithKickEmotes(KCStr(KCDict(metadata[@"original_message"])[@"content"]) ?: @"", nil);
        }
    }
    KCCleanMessageText(m);
    if (!m.slug.length) return nil;
    if (!m.text.length && !m.emotes.count) return nil;
    return m;
}

+ (instancetype)noticeWithText:(NSString *)text
{
    KCChatMessage *m = [[KCChatMessage alloc] init];
    m.kind = KCChatKindNotice;
    m.systemText = text ?: @"";
    m.text = @"";
    m.timestamp = [NSDate date];
    m.badges = @[];
    m.emotes = @[];
    return m;
}

+ (instancetype)userNoticeWithText:(NSString *)text type:(NSString *)type
{
    KCChatMessage *m = [self noticeWithText:text];
    m.kind = KCChatKindUserNotice;
    m.noticeType = type;
    m.systemText = [KCUtils displayText:text ?: @""];
    return m;
}

- (NSString *)nameForDisplay
{
    if (!self.displayName.length) return self.slug ?: @"";
    if (!self.slug.length || [[self.displayName lowercaseString] isEqualToString:self.slug]) return self.displayName;
    return [NSString stringWithFormat:@"%@ (%@)", self.displayName, self.slug];
}

- (NSString *)colorKey
{
    if (self.colorHex.length) return self.colorHex;
    // a stable colour from the name for the rare user without one
    static NSArray *palette;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        palette = @[ @"#53FC18", @"#00C7FF", @"#FF5C5C", @"#FFC700", @"#BC66FF", @"#FF8A3D", @"#4CD4B0", @"#FF6FB5",
                     @"#7EA6FF", @"#E4E44C", @"#3DDC84", @"#FF9F6E" ];
    });
    NSString *name = self.slug ?: @"";
    if (!name.length) return palette[0];
    NSUInteger n = [name characterAtIndex:0] + [name characterAtIndex:name.length - 1];
    return palette[n % palette.count];
}

@end
