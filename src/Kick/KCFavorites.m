#import "KCFavorites.h"
#import "KCCommon.h"

static NSString * const kFavoritesKey = @"favorites";   // @[ @{ @"slug", @"name", @"avatar" } ]
static const NSUInteger KCMaxFavorites = 100;             // (each one is a request of its own when the list loads)

@interface KCFavorites ()
@property (nonatomic, strong) NSMutableArray *items;
@end

@implementation KCFavorites

+ (instancetype)shared
{
    static KCFavorites *favorites;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ favorites = [[KCFavorites alloc] init]; });
    return favorites;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _items = [NSMutableArray array];
        for (id d in [[NSUserDefaults standardUserDefaults] arrayForKey:kFavoritesKey]) {
            if ([d isKindOfClass:[NSDictionary class]] && [KCStr(d[@"slug"]) length]) [_items addObject:[d mutableCopy]];
        }
    }
    return self;
}

- (void)save
{
    [[NSUserDefaults standardUserDefaults] setObject:self.items forKey:kFavoritesKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:KCFavoritesDidChangeNotification object:self];
}

- (NSMutableDictionary *)itemFor:(NSString *)slug
{
    NSString *l = [slug lowercaseString];
    for (NSMutableDictionary *d in self.items) {
        if ([d[@"slug"] isEqualToString:l]) return d;
    }
    return nil;
}

- (NSArray *)slugs
{
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *d in self.items) [result addObject:d[@"slug"]];
    return result;
}

- (BOOL)contains:(NSString *)slug
{
    return slug.length && [self itemFor:slug] != nil;
}

- (void)add:(NSString *)slug displayName:(NSString *)displayName avatarURL:(NSString *)avatarURL
{
    NSString *l = [slug lowercaseString];
    if (!l.length) return;
    NSMutableDictionary *existing = [self itemFor:l];
    if (existing) {
        if (displayName.length) existing[@"name"] = displayName;
        if (avatarURL.length) existing[@"avatar"] = avatarURL;
        [self save];
        return;
    }
    if (self.items.count >= KCMaxFavorites) [self.items removeObjectAtIndex:0];
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithObject:l forKey:@"slug"];
    if (displayName.length) d[@"name"] = displayName;
    if (avatarURL.length) d[@"avatar"] = avatarURL;
    [self.items addObject:d];
    [self save];
}

- (void)remove:(NSString *)slug
{
    NSMutableDictionary *existing = [self itemFor:slug];
    if (!existing) return;
    [self.items removeObjectIdenticalTo:existing];
    [self save];
}

- (void)toggle:(KCChannel *)channel
{
    if (!channel.slug.length) return;
    if ([self contains:channel.slug]) [self remove:channel.slug];
    else [self add:channel.slug displayName:channel.displayName avatarURL:channel.avatarURL];
}

- (NSString *)displayNameFor:(NSString *)slug
{
    NSString *name = KCStr([self itemFor:slug][@"name"]);
    return name.length ? name : slug;
}

- (NSString *)avatarURLFor:(NSString *)slug
{
    return KCStr([self itemFor:slug][@"avatar"]);
}

- (void)rememberChannel:(KCChannel *)channel
{
    NSMutableDictionary *existing = [self itemFor:channel.slug];
    if (!existing) return;
    BOOL changed = NO;
    if (channel.displayName.length && ![existing[@"name"] isEqualToString:channel.displayName]) { existing[@"name"] = channel.displayName; changed = YES; }
    if (channel.avatarURL.length && ![existing[@"avatar"] isEqualToString:channel.avatarURL]) { existing[@"avatar"] = channel.avatarURL; changed = YES; }
    if (changed) {
        [[NSUserDefaults standardUserDefaults] setObject:self.items forKey:kFavoritesKey];
    }
}

@end
