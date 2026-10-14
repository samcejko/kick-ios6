#import <UIKit/UIKit.h>
#import "KCModels.h"

// Opening things from anywhere in the app: the player (full screen), channel and category pages (pushed)
@interface KCNavigator : NSObject

+ (void)openStream:(KCStream *)stream from:(UIViewController *)controller;
+ (void)openChannelSlug:(NSString *)slug from:(UIViewController *)controller;   // the channel page
+ (void)watchChannelSlug:(NSString *)slug from:(UIViewController *)controller;  // the player, straight away
+ (void)openCategory:(KCCategory *)category from:(UIViewController *)controller;
+ (void)openVideo:(KCVideo *)video from:(UIViewController *)controller;
+ (void)openClip:(KCClip *)clip from:(UIViewController *)controller;

// A kick.com web address ("https://kick.com/xqc", "kick.com/xqc/videos") → the channel's slug; nil for the site's
// other pages (categories, search…) and for other sites. The logic of kicker:open?url=, shared with tapped links.
+ (NSString *)channelSlugInKickURL:(NSURL *)url;
// Opens what a kick.com address points to inside the app: YES when it was a channel (its page opens)
+ (BOOL)openKickURL:(NSURL *)url from:(UIViewController *)controller;

// The controller to present modal screens from (the top of the current stack)
+ (UIViewController *)presenterFrom:(UIViewController *)controller;

@end
