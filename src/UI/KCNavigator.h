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

// The controller to present modal screens from (the top of the current stack)
+ (UIViewController *)presenterFrom:(UIViewController *)controller;

@end
