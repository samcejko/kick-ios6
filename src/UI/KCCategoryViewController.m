#import "KCCategoryViewController.h"
#import "KCGridViewController.h"
#import "KCVideoListViewController.h"
#import "KCImageLoader.h"
#import "KCAPI.h"
#import "KCTheme.h"
#import "KCUtils.h"
#import "KCCommon.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kHeaderHeight = 104;

@interface KCCategoryViewController ()
@property (nonatomic, strong) KCCategory *category;
@property (nonatomic, strong) KCHTTPTask *detailTask;
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) KCImageView *picture;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *numbersLabel;
@property (nonatomic, strong) UISegmentedControl *segments;
@property (nonatomic, strong) KCGridViewController *streams;
@property (nonatomic, strong) KCVideoListViewController *clips;
@property (nonatomic, strong) UIViewController *current;
@end

@implementation KCCategoryViewController

- (instancetype)initWithCategory:(KCCategory *)category
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _category = category;
        self.title = [category title];
    }
    return self;
}

- (void)dealloc
{
    [self.detailTask cancel];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    KCCategory *category = self.category;

    self.header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, kHeaderHeight)];
    self.picture = [[KCImageView alloc] initWithFrame:CGRectZero];
    self.picture.contentMode = UIViewContentModeScaleAspectFill;
    self.picture.clipsToBounds = YES;
    self.picture.layer.cornerRadius = 3;
    self.picture.maxPixels = 400;
    [self.header addSubview:self.picture];
    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.nameLabel.backgroundColor = [UIColor clearColor];
    self.nameLabel.font = [UIFont boldSystemFontOfSize:18];
    self.nameLabel.numberOfLines = 2;
    [self.header addSubview:self.nameLabel];
    self.numbersLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.numbersLabel.backgroundColor = [UIColor clearColor];
    self.numbersLabel.font = [UIFont systemFontOfSize:13];
    [self.header addSubview:self.numbersLabel];
    self.segments = [[UISegmentedControl alloc] initWithItems:@[ L(@"Live Channels"), L(@"Clips") ]];
    self.segments.segmentedControlStyle = UISegmentedControlStyleBar;
    self.segments.selectedSegmentIndex = 0;
    [self.segments addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];
    [self.header addSubview:self.segments];
    [self.view addSubview:self.header];
    [self showCategory];

    self.streams = [[KCGridViewController alloc] initWithKind:KCGridKindStreams loader:^KCHTTPTask *(NSString *cursor, KCListCompletion completion) {
        return [KCAPI streamsForCategory:category after:cursor completion:completion];
    }];
    self.streams.emptyText = L(@"Nobody is streaming this right now.");
    self.clips = [[KCVideoListViewController alloc] initWithLoader:^KCHTTPTask *(NSString *cursor, KCListCompletion completion) {
        return [KCAPI clipsForCategory:category period:KCClipPeriodWeek after:cursor completion:completion];
    }];
    self.clips.emptyText = L(@"No clips this week.");
    [self showChild:self.streams];
    [self applyTheme];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:KCThemeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsChanged) name:KCSettingsDidChangeNotification object:nil];

    // (a category from a stream or a search result knows little more than its name: the rest is looked up)
    __weak KCCategoryViewController *weakSelf = self;
    self.detailTask = [KCAPI category:category.slug completion:^(KCCategory *full, NSError *error) {
        KCCategoryViewController *s = weakSelf;
        if (!s) return;
        s.detailTask = nil;
        if (!full) return;
        if (!s.category.imageURL.length) s.category.imageURL = full.imageURL;
        if (!s.category.parentName.length) s.category.parentName = full.parentName;
        s.category.viewers = full.viewers;
        s.category.followers = full.followers;
        [s showCategory];
    }];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[KCTheme shared] applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGRect b = self.view.bounds;
    self.header.frame = CGRectMake(0, 0, b.size.width, kHeaderHeight);
    self.picture.frame = CGRectMake(12, 10, 42, 56);
    CGFloat x = 66;
    self.nameLabel.frame = CGRectMake(x, 8, b.size.width - x - 12, 40);
    self.numbersLabel.frame = CGRectMake(x, 48, b.size.width - x - 12, 16);
    CGFloat segW = MIN(b.size.width - 24, 320);
    self.segments.frame = CGRectMake(12, kHeaderHeight - 36, segW, 30);
    self.current.view.frame = CGRectMake(0, kHeaderHeight, b.size.width, b.size.height - kHeaderHeight);
}

- (void)showCategory
{
    KCCategory *c = self.category;
    [self.picture setImageURL:c.imageURL placeholder:[[KCTheme shared] categoryPlaceholder]];
    self.nameLabel.text = [c title];
    NSMutableArray *parts = [NSMutableArray array];
    if (c.viewers > 0) [parts addObject:[KCUtils formatViewers:c.viewers]];
    if (c.followers > 0) [parts addObject:[NSString stringWithFormat:L(@"%@ followers"), [KCUtils formatCount:c.followers]]];
    if (!parts.count && c.parentName.length) [parts addObject:c.parentName];
    self.numbersLabel.text = [parts componentsJoinedByString:@" · "];
}

- (void)applyTheme
{
    KCTheme *t = [KCTheme shared];
    self.view.backgroundColor = [t backgroundColor];
    self.header.backgroundColor = [t cardColor];
    self.nameLabel.textColor = [t primaryTextColor];
    self.numbersLabel.textColor = [t secondaryTextColor];
}

- (void)settingsChanged
{
    [self.streams reloadKeepingItemsIfPossible];   // (the language filter)
}

- (void)showChild:(UIViewController *)child
{
    if (self.current == child) return;
    if (self.current) {
        [self.current willMoveToParentViewController:nil];
        [self.current.view removeFromSuperview];
        [self.current removeFromParentViewController];
    }
    self.current = child;
    [self addChildViewController:child];
    CGRect b = self.view.bounds;
    child.view.frame = CGRectMake(0, kHeaderHeight, b.size.width, b.size.height - kHeaderHeight);
    [self.view addSubview:child.view];
    [child didMoveToParentViewController:self];
}

- (void)segmentChanged
{
    [self showChild:self.segments.selectedSegmentIndex == 1 ? (UIViewController *)self.clips : (UIViewController *)self.streams];
}

@end
