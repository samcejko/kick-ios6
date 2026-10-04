#import "KCSearchViewController.h"
#import "KCStreamCell.h"
#import "KCAPI.h"
#import "KCSettings.h"
#import "KCNavigator.h"
#import "KCTheme.h"
#import "KCUtils.h"
#import "KCCommon.h"

typedef NS_ENUM(NSInteger, KCSearchSection) {
    KCSearchSectionChannels = 0,
    KCSearchSectionCategories,
    KCSearchSectionCount,
};

@interface KCSearchViewController () <UISearchBarDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray *channels;
@property (nonatomic, strong) NSArray *categories;
@property (nonatomic, strong) NSArray *recent;
@property (nonatomic, strong) KCHTTPTask *task;
@property (nonatomic, copy) NSString *query;          // what the results belong to
@property (nonatomic) BOOL searching;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *messageLabel;
@end

@implementation KCSearchViewController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = L(@"Search");
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
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = L(@"Channels and categories");
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.tableView.tableHeaderView = self.searchBar;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    [self.tableView addSubview:self.spinner];
    self.messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.messageLabel.backgroundColor = [UIColor clearColor];
    self.messageLabel.numberOfLines = 0;
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.font = [UIFont systemFontOfSize:15];
    self.messageLabel.hidden = YES;
    [self.tableView addSubview:self.messageLabel];

    self.recent = [KCSettings recentSearches];
    [self applyTheme];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:KCThemeDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[KCTheme shared] applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGRect b = self.tableView.bounds;
    self.spinner.center = CGPointMake(b.size.width / 2, 100);
    self.messageLabel.frame = CGRectMake(30, 80, b.size.width - 60, 80);
}

- (void)applyTheme
{
    KCTheme *t = [KCTheme shared];
    [t applyToTableView:self.tableView];
    self.tableView.backgroundColor = [t cardColor];
    [t applyToSearchBar:self.searchBar];
    self.spinner.activityIndicatorViewStyle = [t spinnerStyle];
    self.messageLabel.textColor = [t secondaryTextColor];
    [self.tableView reloadData];
}

#pragma mark - Searching

- (BOOL)showsRecent
{
    return self.query.length == 0;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(searchNow) object:nil];
    NSString *text = [searchText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!text.length) {
        [self.task cancel];
        self.task = nil;
        self.query = @"";
        self.channels = nil;
        self.categories = nil;
        self.searching = NO;
        [self.spinner stopAnimating];
        self.messageLabel.hidden = YES;
        [self.tableView reloadData];
        return;
    }
    [self performSelector:@selector(searchNow) withObject:nil afterDelay:0.5];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(searchNow) object:nil];
    [searchBar resignFirstResponder];
    [self searchNow];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    [searchBar resignFirstResponder];
}

- (void)searchFor:(NSString *)text
{
    [self view];   // (loads the view, and the search bar with it)
    self.searchBar.text = text;
    [self.searchBar resignFirstResponder];
    [self searchNow];
}

- (void)searchNow
{
    NSString *text = [self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!text.length) return;
    [self.task cancel];
    self.query = text;
    self.searching = YES;
    self.messageLabel.hidden = YES;
    if (!self.channels.count && !self.categories.count) [self.spinner startAnimating];
    [KCSettings addRecentSearch:text];
    self.recent = [KCSettings recentSearches];
    __weak KCSearchViewController *weakSelf = self;
    self.task = [KCAPI search:text completion:^(NSArray *channels, NSArray *categories, NSError *error) {
        KCSearchViewController *s = weakSelf;
        if (!s) return;
        s.task = nil;
        s.searching = NO;
        [s.spinner stopAnimating];
        if (error) {
            s.messageLabel.text = error.localizedDescription;
            s.messageLabel.hidden = NO;
            return;
        }
        s.channels = channels;
        s.categories = categories;
        [s.tableView reloadData];
        if (!channels.count && !categories.count) {
            s.messageLabel.text = L(@"No channel or category with this name.");
            s.messageLabel.hidden = NO;
        }
    }];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self showsRecent] ? 1 : KCSearchSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if ([self showsRecent]) return (NSInteger)self.recent.count + (self.recent.count ? 1 : 0);
    return section == KCSearchSectionChannels ? (NSInteger)self.channels.count : (NSInteger)self.categories.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if ([self showsRecent]) return self.recent.count ? L(@"Recent searches") : nil;
    if (section == KCSearchSectionChannels) return self.channels.count ? L(@"Channels") : nil;
    return self.categories.count ? L(@"Categories") : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [self showsRecent] ? 44 : [KCChannelCell height];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    KCTheme *t = [KCTheme shared];
    if ([self showsRecent]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"recent"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"recent"];
        [t styleCell:cell];
        if ((NSUInteger)indexPath.row < self.recent.count) {
            cell.textLabel.text = self.recent[(NSUInteger)indexPath.row];
            cell.textLabel.font = [UIFont systemFontOfSize:16];
            cell.textLabel.textAlignment = NSTextAlignmentLeft;
            cell.textLabel.textColor = [t primaryTextColor];
        } else {
            cell.textLabel.text = L(@"Clear recent searches");
            cell.textLabel.font = [UIFont systemFontOfSize:15];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.textColor = [t secondaryTextColor];
        }
        return cell;
    }
    KCChannelCell *cell = [tableView dequeueReusableCellWithIdentifier:[KCChannelCell reuseIdentifier] forIndexPath:indexPath];
    if (indexPath.section == KCSearchSectionChannels) {
        [cell configureWithChannel:self.channels[(NSUInteger)indexPath.row]];
    } else {
        KCCategory *category = self.categories[(NSUInteger)indexPath.row];
        NSString *detail = category.viewers > 0 ? [KCUtils formatViewers:category.viewers] : (category.parentName.length ? category.parentName : L(@"Category"));
        [cell configureWithSlug:category.slug displayName:[category title] avatarURL:category.imageURL detail:detail];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self showsRecent]) {
        if ((NSUInteger)indexPath.row < self.recent.count) {
            self.searchBar.text = self.recent[(NSUInteger)indexPath.row];
            [self.searchBar resignFirstResponder];
            [self searchNow];
        } else {
            [KCSettings clearRecentSearches];
            self.recent = @[];
            [tableView reloadData];
        }
        return;
    }
    [self.searchBar resignFirstResponder];
    if (indexPath.section == KCSearchSectionChannels) {
        KCChannel *c = self.channels[(NSUInteger)indexPath.row];
        if (c.stream) [KCNavigator openStream:c.stream from:self];
        else [KCNavigator openChannelSlug:c.slug from:self];
    } else {
        [KCNavigator openCategory:self.categories[(NSUInteger)indexPath.row] from:self];
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    [self.searchBar resignFirstResponder];
}

@end
