#import <UIKit/UIKit.h>
#import "KCVideoListViewController.h"
#import "KCModels.h"

// A channel: banner, avatar, name, followers, description, "Watch" when live, the star for the favourites, and
// below the segmented list of past broadcasts and clips.
@interface KCChannelViewController : KCVideoListViewController
- (instancetype)initWithSlug:(NSString *)slug;
@property (nonatomic, readonly, copy) NSString *slug;
@property (nonatomic) BOOL showsDoneButton;   // when presented modally (from the player)
@end
