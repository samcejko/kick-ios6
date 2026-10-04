#import <UIKit/UIKit.h>
#import "KCGridViewController.h"

// A paged table of videos or clips (KCVideo / KCClip items) with pull-to-refresh and "load more"; the base of the
// channel page. An optional view is shown as a sticky section header (segmented controls).
@interface KCVideoListViewController : UITableViewController

- (instancetype)initWithLoader:(KCGridLoader)loader;

@property (nonatomic, copy) KCGridLoader loader;
@property (nonatomic, readonly, strong) NSArray *items;
@property (nonatomic, copy) NSString *emptyText;
@property (nonatomic, strong) UIView *segmentHeaderView;      // 44 pt, sticks to the top while scrolling
@property (nonatomic) BOOL loadsOnAppear;                     // default YES
@property (nonatomic, copy) void (^onSelectItem)(id item);

- (void)reload;
- (void)applyTheme;
- (void)showMessage:(NSString *)text;                          // the grey text over the empty list (nil hides it)

@end
