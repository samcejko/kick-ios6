#import <UIKit/UIKit.h>

// The tab bar: Live, Categories, Favorites, Search, Settings
@interface KCRootViewController : UITabBarController
- (void)applyTheme;
// Deep links (kicker:channel/<slug>, kicker:open?channel=<slug>, kicker:search?q=<text>)
- (void)openChannelSlug:(NSString *)slug watch:(BOOL)watch;
- (void)searchFor:(NSString *)text;
@end

// The live channels tab: a grid with the language filter in the navigation bar
@interface KCBrowseViewController : UIViewController
@end
