#import "KCRootViewController.h"
#import "KCGridViewController.h"
#import "KCFavoritesViewController.h"
#import "KCSearchViewController.h"
#import "KCSettingsViewController.h"
#import "KCNavigator.h"
#import "KCAPI.h"
#import "KCSettings.h"
#import "KCTheme.h"
#import "KCCommon.h"

#pragma mark - Browse

@interface KCBrowseViewController () <UIActionSheetDelegate>
@property (nonatomic, strong) KCGridViewController *grid;
@property (nonatomic, strong) UIBarButtonItem *languageItem;
@end

@implementation KCBrowseViewController

- (instancetype)init
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) self.title = L(@"Live");
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.grid = [[KCGridViewController alloc] initWithKind:KCGridKindStreams loader:^KCHTTPTask *(NSString *cursor, KCListCompletion completion) {
        return [KCAPI topStreamsAfter:cursor completion:completion];
    }];
    self.grid.emptyText = L(@"No live channels for this language right now.");
    [self addChildViewController:self.grid];
    self.grid.view.frame = self.view.bounds;
    self.grid.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.grid.view];
    [self.grid didMoveToParentViewController:self];
    self.languageItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStyleBordered target:self action:@selector(languageTapped)];
    self.navigationItem.rightBarButtonItem = self.languageItem;
    [self updateLanguageItem];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsChanged) name:KCSettingsDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[KCTheme shared] applyToNavigationBar:self.navigationController.navigationBar];
}

+ (NSArray *)languages
{
    // code, name (the languages most streamed in on Kick; "" = all)
    return @[ @[@"", L(@"All languages")], @[@"cs", @"Čeština"], @[@"sk", @"Slovenčina"], @[@"en", @"English"], @[@"es", @"Español"],
              @[@"pt", @"Português"], @[@"de", @"Deutsch"], @[@"fr", @"Français"], @[@"it", @"Italiano"], @[@"pl", @"Polski"],
              @[@"tr", @"Türkçe"], @[@"ru", @"Русский"], @[@"uk", @"Українська"], @[@"ar", @"العربية"] ];
}

- (void)updateLanguageItem
{
    NSString *code = [KCSettings streamLanguage];
    NSString *title = L(@"Language");
    for (NSArray *l in [KCBrowseViewController languages]) {
        if ([l[0] isEqualToString:code] && code.length) title = l[1];
    }
    self.languageItem.title = title;
}

- (void)languageTapped
{
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:L(@"Show channels streaming in") delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    for (NSArray *l in [KCBrowseViewController languages]) [sheet addButtonWithTitle:l[1]];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    if (KCIsPad()) [sheet showFromBarButtonItem:self.languageItem animated:YES];
    else [sheet showFromTabBar:self.tabBarController.tabBar];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    NSArray *languages = [KCBrowseViewController languages];
    if (buttonIndex < 0 || buttonIndex >= (NSInteger)languages.count) return;
    [KCSettings setStreamLanguage:languages[(NSUInteger)buttonIndex][0]];
    [KCSettings save];
    [self updateLanguageItem];
    [self.grid reload];
}

- (void)settingsChanged
{
    [self updateLanguageItem];
}

@end

#pragma mark - Root

@interface KCRootViewController () <UITabBarControllerDelegate>
@property (nonatomic, strong) UINavigationController *browseNav;
@property (nonatomic, strong) UINavigationController *categoriesNav;
@property (nonatomic, strong) UINavigationController *favoritesNav;
@property (nonatomic, strong) UINavigationController *searchNav;
@property (nonatomic, strong) UINavigationController *settingsNav;
@end

@implementation KCRootViewController

- (instancetype)init
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        KCTheme *t = [KCTheme shared];
        KCBrowseViewController *browse = [[KCBrowseViewController alloc] init];
        browse.tabBarItem = [[UITabBarItem alloc] initWithTitle:L(@"Live") image:[t tabIconBrowse] tag:0];
        _browseNav = [[UINavigationController alloc] initWithRootViewController:browse];

        KCGridViewController *categories = [[KCGridViewController alloc] initWithKind:KCGridKindCategories loader:^KCHTTPTask *(NSString *cursor, KCListCompletion completion) {
            return [KCAPI topCategoriesAfter:cursor completion:completion];
        }];
        categories.title = L(@"Categories");
        categories.tabBarItem = [[UITabBarItem alloc] initWithTitle:L(@"Categories") image:[t tabIconCategories] tag:1];
        _categoriesNav = [[UINavigationController alloc] initWithRootViewController:categories];

        KCFavoritesViewController *favorites = [[KCFavoritesViewController alloc] init];
        favorites.tabBarItem = [[UITabBarItem alloc] initWithTitle:L(@"Favorites") image:[t tabIconFavorites] tag:2];
        _favoritesNav = [[UINavigationController alloc] initWithRootViewController:favorites];

        KCSearchViewController *search = [[KCSearchViewController alloc] init];
        search.tabBarItem = [[UITabBarItem alloc] initWithTitle:L(@"Search") image:[t tabIconSearch] tag:3];
        _searchNav = [[UINavigationController alloc] initWithRootViewController:search];

        KCSettingsViewController *settings = [[KCSettingsViewController alloc] init];
        settings.tabBarItem = [[UITabBarItem alloc] initWithTitle:L(@"Settings") image:[t tabIconSettings] tag:4];
        _settingsNav = [[UINavigationController alloc] initWithRootViewController:settings];

        self.viewControllers = @[ _browseNav, _categoriesNav, _favoritesNav, _searchNav, _settingsNav ];
        NSInteger last = [[NSUserDefaults standardUserDefaults] integerForKey:@"lastTab"];
        self.selectedIndex = (NSUInteger)((last >= 0 && last <= 4) ? last : 0);
        self.delegate = self;
        [self applyTheme];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:KCThemeDidChangeNotification object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme
{
    KCTheme *t = [KCTheme shared];
    for (UINavigationController *nav in self.viewControllers) [t applyToNavigationBar:nav.navigationBar];
    [t applyToTabBar:self.tabBar];
    [[UIApplication sharedApplication] setStatusBarStyle:[t statusBarStyle] animated:NO];
}

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController
{
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)self.selectedIndex forKey:@"lastTab"];
}

- (void)openChannelSlug:(NSString *)slug watch:(BOOL)watch
{
    if (watch) [KCNavigator watchChannelSlug:slug from:self];
    else {
        self.selectedViewController = self.searchNav;
        [KCNavigator openChannelSlug:slug from:self.searchNav];
    }
}

- (void)searchFor:(NSString *)text
{
    [self.presentedViewController dismissViewControllerAnimated:NO completion:nil];
    self.selectedViewController = self.searchNav;
    [self.searchNav popToRootViewControllerAnimated:NO];
    KCSearchViewController *search = (KCSearchViewController *)self.searchNav.viewControllers[0];
    [search searchFor:text];
}

#pragma mark - Rotation

- (BOOL)shouldAutorotate
{
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return KCIsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;
}

@end
