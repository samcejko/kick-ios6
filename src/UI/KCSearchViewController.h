#import <UIKit/UIKit.h>

// The "Search" tab: channels and categories by name, recent searches
@interface KCSearchViewController : UITableViewController
- (void)searchFor:(NSString *)text;   // (the kicker:search?q= link)
@end
