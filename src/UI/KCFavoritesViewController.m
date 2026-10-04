#import "KCFavoritesViewController.h"
#import "KCStreamCell.h"
#import "KCAPI.h"
#import "KCFavorites.h"
#import "KCNavigator.h"
#import "KCTheme.h"
#import "KCUtils.h"
#import "KCCommon.h"

typedef NS_ENUM(NSInteger, KCFavoritesSection) {
    KCFavoritesSectionLive = 0,
    KCFavoritesSectionOffline,
    KCFavoritesSectionCount,
};

static const NSTimeInterval KCFavoritesStaleAfter = 90;

@interface KCFavoritesViewController ()
@property (nonatomic, strong) NSArray *live;          // KCChannel with a stream
@property (nonatomic, strong) NSArray *offline;       // KCChannel, or @{slug, name, avatar} while it is not known yet
@property (nonatomic, strong) NSMutableDictionary *channels;   // slug -> KCChannel
@property (nonatomic, strong) KCHTTPTask *task;
@property (nonatomic, strong) NSDate *loadedAt;
@property (nonatomic, strong) NSError *lastError;
@property (nonatomic, strong) UILabel *messageLabel;
@end

@implementation KCFavoritesViewController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = L(@"Favorites");
        _channels = [NSMutableDictionary dictionary];
        _live = @[];
        _offline = @[];
    }
    return self;
}

- (void)dealloc
{
    [_task cancel];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.tableView registerClass:[KCChannelCell class] forCellReuseIdentifier:[KCChannelCell reuseIdentifier]];
    self.tableView.rowHeight = [KCChannelCell height];
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];   // (no separator lines below the last row)
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.leftBarButtonItem = self.editButtonItem;

    self.messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.messageLabel.backgroundColor = [UIColor clearColor];
    self.messageLabel.numberOfLines = 0;
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.font = [UIFont systemFontOfSize:15];
    self.messageLabel.hidden = YES;
    [self.tableView addSubview:self.messageLabel];

    [self applyTheme];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(applyTheme) name:KCThemeDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(favoritesChanged) name:KCFavoritesDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[KCTheme shared] applyToNavigationBar:self.navigationController.navigationBar];
    if (!self.loadedAt || -[self.loadedAt timeIntervalSinceNow] > KCFavoritesStaleAfter) [self reload];
    else [self rebuild];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGRect b = self.tableView.bounds;
    self.messageLabel.frame = CGRectMake(30, 90, b.size.width - 60, 120);
}

- (void)applyTheme
{
    KCTheme *t = [KCTheme shared];
    [t applyToTableView:self.tableView];
    self.tableView.backgroundColor = [t cardColor];
    self.messageLabel.textColor = [t secondaryTextColor];
    self.refreshControl.tintColor = t.isDark ? [UIColor whiteColor] : nil;
    [self.tableView reloadData];
}

#pragma mark - Loading

- (void)reload
{
    [self.task cancel];
    self.task = nil;
    self.lastError = nil;
    NSArray *slugs = [[KCFavorites shared] slugs];
    if (!slugs.count) {
        [self.refreshControl endRefreshing];
        self.loadedAt = [NSDate date];
        [self rebuild];
        return;
    }
    __weak KCFavoritesViewController *weakSelf = self;
    self.task = [KCAPI channels:slugs completion:^(NSArray *channels, NSError *error) {
        KCFavoritesViewController *s = weakSelf;
        if (!s) return;
        s.task = nil;
        [s.refreshControl endRefreshing];
        if (error && !channels.count) s.lastError = error;
        else s.loadedAt = [NSDate date];
        for (KCChannel *c in channels) {
            s.channels[c.slug] = c;
            [[KCFavorites shared] rememberChannel:c];
        }
        [s rebuild];
    }];
}

// Live first (most viewers first), then the rest by name
- (void)rebuild
{
    NSMutableArray *live = [NSMutableArray array];
    NSMutableArray *offline = [NSMutableArray array];
    KCFavorites *favorites = [KCFavorites shared];
    for (NSString *slug in [favorites slugs]) {
        KCChannel *c = self.channels[slug];
        if (c.stream) [live addObject:c];
        else if (c) [offline addObject:c];
        else [offline addObject:@{ @"slug": slug, @"name": [favorites displayNameFor:slug], @"avatar": [favorites avatarURLFor:slug] ?: @"" }];
    }
    [live sortUsingComparator:^NSComparisonResult(KCChannel *a, KCChannel *b) {
        NSInteger va = a.stream.viewers, vb = b.stream.viewers;
        return va > vb ? NSOrderedAscending : (va < vb ? NSOrderedDescending : NSOrderedSame);
    }];
    [offline sortUsingComparator:^NSComparisonResult(id a, id b) {
        NSString *na = [a isKindOfClass:[KCChannel class]] ? [(KCChannel *)a displayName] : a[@"name"];
        NSString *nb = [b isKindOfClass:[KCChannel class]] ? [(KCChannel *)b displayName] : b[@"name"];
        return [na ?: @"" caseInsensitiveCompare:nb ?: @""];
    }];
    self.live = live;
    self.offline = offline;
    [self.tableView reloadData];
    if (!live.count && !offline.count) {
        self.messageLabel.text = L(@"No favorites yet. Open a channel and tap the star to keep it here.");
        self.messageLabel.hidden = NO;
    } else if (self.lastError && !live.count) {
        // (the names are known, whether they are live is not)
        self.messageLabel.hidden = YES;
        [KCUtils alertWithTitle:L(@"Could not refresh") message:self.lastError.localizedDescription];
        self.lastError = nil;
    } else {
        self.messageLabel.hidden = YES;
    }
}

- (void)favoritesChanged
{
    // a new favourite: whether it is live is not known yet, so ask again
    BOOL unknown = NO;
    for (NSString *slug in [[KCFavorites shared] slugs]) if (!self.channels[slug]) unknown = YES;
    if (unknown && self.isViewLoaded && self.view.window) [self reload];
    else [self rebuild];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return KCFavoritesSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == KCFavoritesSectionLive ? (NSInteger)self.live.count : (NSInteger)self.offline.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == KCFavoritesSectionLive) return self.live.count ? L(@"Live now") : nil;
    return self.offline.count ? L(@"Offline") : nil;
}

- (id)itemAtIndexPath:(NSIndexPath *)indexPath
{
    NSArray *list = indexPath.section == KCFavoritesSectionLive ? self.live : self.offline;
    return (NSUInteger)indexPath.row < list.count ? list[(NSUInteger)indexPath.row] : nil;
}

- (NSString *)slugAtIndexPath:(NSIndexPath *)indexPath
{
    id item = [self itemAtIndexPath:indexPath];
    if ([item isKindOfClass:[KCChannel class]]) return [(KCChannel *)item slug];
    return KCStr(KCDict(item)[@"slug"]);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    KCChannelCell *cell = [tableView dequeueReusableCellWithIdentifier:[KCChannelCell reuseIdentifier] forIndexPath:indexPath];
    id item = [self itemAtIndexPath:indexPath];
    if ([item isKindOfClass:[KCChannel class]]) {
        [cell configureWithChannel:item];
    } else {
        NSDictionary *d = KCDict(item);
        NSString *avatar = [KCStr(d[@"avatar"]) length] ? d[@"avatar"] : nil;
        [cell configureWithSlug:d[@"slug"] displayName:d[@"name"] avatarURL:avatar detail:L(@"Offline")];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id item = [self itemAtIndexPath:indexPath];
    if ([item isKindOfClass:[KCChannel class]] && [(KCChannel *)item stream]) { [KCNavigator openStream:[(KCChannel *)item stream] from:self]; return; }
    [KCNavigator openChannelSlug:[self slugAtIndexPath:indexPath] from:self];
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return L(@"Remove");
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    NSString *slug = [self slugAtIndexPath:indexPath];
    if (slug.length) [[KCFavorites shared] remove:slug];
}

@end
