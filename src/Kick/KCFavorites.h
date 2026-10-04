#import <Foundation/Foundation.h>
#import "KCModels.h"

// Channels marked on this device (no account needed). Posts KCFavoritesDidChangeNotification on every change.
@interface KCFavorites : NSObject

+ (instancetype)shared;

- (NSArray *)slugs;                                  // in the order they were added
- (BOOL)contains:(NSString *)slug;
- (void)add:(NSString *)slug displayName:(NSString *)displayName avatarURL:(NSString *)avatarURL;
- (void)remove:(NSString *)slug;
- (void)toggle:(KCChannel *)channel;
- (NSString *)displayNameFor:(NSString *)slug;       // the last name seen
- (NSString *)avatarURLFor:(NSString *)slug;
- (void)rememberChannel:(KCChannel *)channel;         // refreshes the stored name and picture

@end
