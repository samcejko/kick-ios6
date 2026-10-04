#import <UIKit/UIKit.h>
#import "KCModels.h"

// Watching: a live channel with its chat, a past broadcast with the chat replay, or a clip. Presented full screen.
@interface KCPlayerViewController : UIViewController

- (instancetype)initWithChannelSlug:(NSString *)slug stream:(KCStream *)stream;   // stream may be nil (looked up)
- (instancetype)initWithVideo:(KCVideo *)video;
- (instancetype)initWithClip:(KCClip *)clip;

// Another player takes this screen's place (a channel opened from inside the player)
- (void)replaceWithPlayer:(KCPlayerViewController *)player;

@end
