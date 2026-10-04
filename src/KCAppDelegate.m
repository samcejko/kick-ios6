#import "KCAppDelegate.h"
#import "KCRootViewController.h"
#import "KCNavigator.h"
#import "KCTLSSocket.h"
#import "KCMediaProxy.h"
#import "KCImageLoader.h"
#import "KCSettings.h"
#import "KCTheme.h"
#import "KCUtils.h"
#import "KCCommon.h"
#include <dlfcn.h>
#include <signal.h>
#include <mach/mach.h>

// A button "named" text: by its title or by its accessibility label (icon buttons have no title), case does not matter
static BOOL KCButtonMatches(UIButton *button, NSString *text)
{
    for (NSString *name in @[ button.currentTitle ?: @"", button.accessibilityLabel ?: @"" ]) {
        if (name.length && [name rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

// Is the text in a label of this view? (Controls' own labels excepted: a segment title is not its table row's text.)
static BOOL KCViewContainsText(UIView *view, NSString *text)
{
    if ([view isKindOfClass:[UILabel class]]) {
        NSString *s = ((UILabel *)view).text;
        return s.length && [s rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound;
    }
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UIControl class]]) continue;
        if (KCViewContainsText(sub, text)) return YES;
    }
    return NO;
}

// Acts on a view "named" text the way a finger would: a button is pressed, a segment selected, the switch of a table
// row flipped, a table or grid row selected. YES when this view was the one.
static BOOL KCPressView(UIView *v, NSString *text)
{
    if ([v isKindOfClass:[UIButton class]]) {
        if (!KCButtonMatches((UIButton *)v, text)) return NO;
        [(UIButton *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }
    if ([v isKindOfClass:[UISegmentedControl class]]) {
        UISegmentedControl *segments = (UISegmentedControl *)v;
        for (NSUInteger i = 0; i < segments.numberOfSegments; i++) {
            NSString *title = [segments titleForSegmentAtIndex:i];
            if (title.length && [title rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound) {
                segments.selectedSegmentIndex = (NSInteger)i;
                [segments sendActionsForControlEvents:UIControlEventValueChanged];
                return YES;
            }
        }
        return NO;
    }
    if ([v isKindOfClass:[UITableViewCell class]]) {
        UITableViewCell *cell = (UITableViewCell *)v;
        if (!KCViewContainsText(cell, text)) return NO;
        if ([cell.accessoryView isKindOfClass:[UISwitch class]]) {
            UISwitch *sw = (UISwitch *)cell.accessoryView;
            [sw setOn:!sw.on animated:NO];
            [sw sendActionsForControlEvents:UIControlEventValueChanged];
            return YES;
        }
        UIView *table = cell.superview;
        while (table && ![table isKindOfClass:[UITableView class]]) table = table.superview;
        NSIndexPath *ip = [(UITableView *)table indexPathForCell:cell];
        id<UITableViewDelegate> delegate = [(UITableView *)table delegate];
        if (!ip || ![delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) return NO;
        [delegate tableView:(UITableView *)table didSelectRowAtIndexPath:ip];
        return YES;
    }
    if ([v isKindOfClass:[UICollectionViewCell class]]) {
        UICollectionViewCell *cell = (UICollectionViewCell *)v;
        if (!KCViewContainsText(cell, text)) return NO;
        UIView *grid = cell.superview;
        while (grid && ![grid isKindOfClass:[UICollectionView class]]) grid = grid.superview;
        NSIndexPath *ip = [(UICollectionView *)grid indexPathForCell:cell];
        id<UICollectionViewDelegate> delegate = [(UICollectionView *)grid delegate];
        if (!ip || ![delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) return NO;
        [delegate collectionView:(UICollectionView *)grid didSelectItemAtIndexPath:ip];
        return YES;
    }
    return NO;
}

@implementation KCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // (a peer that went away must not kill the process while a socket is written to)
    signal(SIGPIPE, SIG_IGN);
    [KCSettings registerDefaults];
    KCLog(@"Kicker %@ starting on %@ (iOS %@)", [KCUtils appVersion], [KCUtils deviceModel], [UIDevice currentDevice].systemVersion);
    [KCTLSSocket warmUp];
    [[KCImageLoader shared] pruneDisk];
    [KCImageLoader shared].animationAllowed = [KCSettings animatedEmotes];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.rootViewController = [[KCRootViewController alloc] init];
    self.window.rootViewController = self.rootViewController;
    self.window.backgroundColor = [[KCTheme shared] backgroundColor];
    [self.window makeKeyAndVisible];
    [application setStatusBarStyle:[[KCTheme shared] statusBarStyle] animated:NO];
    return YES;
}

// kicker:channel/<slug> opens the channel page, kicker:watch/<slug> the player, kicker:open?url=https://kick.com/<slug>
// a channel by its web address and kicker:search?q=<text> the search. Over SSH (uiopen) a few commands help checking
// the app: kicker:snapshot and kicker:screen write tmp/screen.png, kicker:press?n=1 presses a button of the alert on
// screen, press?title=Chat a button, segment, switch row or list row with that text, kicker:tab?n=1 switches the tab,
// kicker:back pops the current page and kicker:stats logs the memory in use. The commands need a file named "debug"
// in the app's Documents folder.
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    NSString *s = url.absoluteString ?: @"";
    if (![s hasPrefix:@"kicker:"]) return NO;
    NSString *target = [s substringFromIndex:@"kicker:".length];
    while ([target hasPrefix:@"/"]) target = [target substringFromIndex:1];
    NSString *query = nil;
    NSRange q = [target rangeOfString:@"?"];
    if (q.location != NSNotFound) {
        query = [target substringFromIndex:q.location + 1];
        target = [target substringToIndex:q.location];
    }
    NSDictionary *params = query.length ? [KCUtils parseQuery:query] : @{};
    if ([target hasPrefix:@"channel/"] || [target hasPrefix:@"watch/"]) {
        BOOL watch = [target hasPrefix:@"watch/"];
        NSString *slug = [[target substringFromIndex:[target rangeOfString:@"/"].location + 1] lowercaseString];
        slug = [slug stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: slug;
        if (slug.length) [self.rootViewController openChannelSlug:slug watch:watch];
        return YES;
    }
    if ([target isEqualToString:@"open"] && [params[@"channel"] length]) {
        [self.rootViewController openChannelSlug:[params[@"channel"] lowercaseString] watch:[params[@"watch"] boolValue]];
        return YES;
    }
    if ([target isEqualToString:@"open"] && [params[@"url"] length]) {
        // a kick.com address: its first path component is the channel ("https://kick.com/xqc", "kick.com/xqc/videos")
        NSString *address = params[@"url"];
        if ([address rangeOfString:@"://"].location == NSNotFound) address = [@"https://" stringByAppendingString:address];
        NSURL *web = [NSURL URLWithString:address];
        NSArray *parts = [web.path componentsSeparatedByString:@"/"];
        NSString *slug = parts.count > 1 ? [parts[1] lowercaseString] : nil;
        BOOL kick = [[web.host lowercaseString] hasSuffix:@"kick.com"];
        if (kick && slug.length && ![@[ @"category", @"categories", @"search", @"browse", @"following" ] containsObject:slug]) {
            [self.rootViewController openChannelSlug:slug watch:NO];
        }
        return YES;
    }
    if ([target isEqualToString:@"search"] && [params[@"q"] length]) {
        [self.rootViewController searchFor:params[@"q"]];
        return YES;
    }
    BOOL debug = [[NSFileManager defaultManager] fileExistsAtPath:[[KCUtils documentsPath] stringByAppendingPathComponent:@"debug"]];
    if (!debug) return YES;
    if ([target isEqualToString:@"stats"]) {
        struct task_basic_info info;
        mach_msg_type_number_t count = TASK_BASIC_INFO_COUNT;
        if (task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &count) == KERN_SUCCESS) {
            KCLog(@"Memory: %.1f MB resident, %.1f MB virtual", info.resident_size / 1048576.0, info.virtual_size / 1048576.0);
        }
        UIViewController *top = [KCNavigator presenterFrom:nil];
        KCLog(@"Windows: %lu, top controller: %@, proxy generation %ld, dark theme %d", (unsigned long)[UIApplication sharedApplication].windows.count,
              NSStringFromClass([top class]), (long)[KCMediaProxy shared].generation, [KCTheme shared].isDark);
        return YES;
    }
    if ([target isEqualToString:@"snapshot"]) {
        // every visible window drawn into one picture (alerts and sheets have windows of their own)
        CGSize size = [UIScreen mainScreen].bounds.size;
        UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.hidden || w.alpha <= 0) continue;
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, w.frame.origin.x, w.frame.origin.y);
            [w.layer renderInContext:ctx];
            CGContextRestoreGState(ctx);
        }
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"screen.png"];
        BOOL ok = [UIImagePNGRepresentation(image) writeToFile:path atomically:YES];
        KCLog(@"Snapshot %@: %@", ok ? @"written to" : @"failed for", path);
        return YES;
    }
    if ([target isEqualToString:@"screen"]) {
        // what the screen really shows, video included (the system's own screen grab, resolved at run time)
        CGImageRef (*grab)(void) = (CGImageRef (*)(void))dlsym(RTLD_DEFAULT, "UIGetScreenImage");
        CGImageRef shot = grab ? grab() : NULL;
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"screen.png"];
        BOOL ok = NO;
        if (shot) {
            ok = [UIImagePNGRepresentation([UIImage imageWithCGImage:shot]) writeToFile:path atomically:YES];
            CGImageRelease(shot);
        }
        KCLog(@"Screen grab %@: %@", ok ? @"written to" : @"failed for", path);
        return YES;
    }
    if ([target isEqualToString:@"press"]) {
        // kicker:press?n=<index> presses a button of the alert or action sheet on screen, press?title=<text> a button with that title
        NSString *byTitle = params[@"title"];
        NSInteger n = [params[@"n"] integerValue];
        NSMutableArray *views = [NSMutableArray array];
        for (UIWindow *w in [UIApplication sharedApplication].windows) [views addObject:w];
        BOOL pressed = NO;
        for (NSUInteger i = 0; i < views.count && !pressed; i++) {
            UIView *v = views[i];
            if (!byTitle.length && [v isKindOfClass:[UIAlertView class]] && ((UIAlertView *)v).visible) {
                UIAlertView *alert = (UIAlertView *)v;
                if ([alert.delegate respondsToSelector:@selector(alertView:clickedButtonAtIndex:)]) [alert.delegate alertView:alert clickedButtonAtIndex:n];
                [alert dismissWithClickedButtonIndex:n animated:NO];
                pressed = YES;
            } else if (!byTitle.length && [v isKindOfClass:[UIActionSheet class]] && ((UIActionSheet *)v).visible) {
                UIActionSheet *sheet = (UIActionSheet *)v;
                if ([sheet.delegate respondsToSelector:@selector(actionSheet:clickedButtonAtIndex:)]) [sheet.delegate actionSheet:sheet clickedButtonAtIndex:n];
                [sheet dismissWithClickedButtonIndex:n animated:NO];
                pressed = YES;
            } else if (byTitle.length && !v.hidden && KCPressView(v, byTitle)) {
                pressed = YES;
            } else {
                [views addObjectsFromArray:v.subviews];
            }
        }
        KCLog(@"Press %@: %@", query ?: @"", pressed ? @"done" : @"nothing found");
        return YES;
    }
    if ([target isEqualToString:@"tab"]) {
        NSInteger n = [params[@"n"] integerValue];
        if (n >= 0 && n < 5) self.rootViewController.selectedIndex = (NSUInteger)n;
        return YES;
    }
    if ([target isEqualToString:@"back"]) {
        // (the back button of a navigation bar is no UIButton on iOS 6, so press?title= cannot reach it)
        UIViewController *top = [KCNavigator presenterFrom:nil];
        if ([top isKindOfClass:[UITabBarController class]]) top = [(UITabBarController *)top selectedViewController];
        UINavigationController *nav = [top isKindOfClass:[UINavigationController class]] ? (UINavigationController *)top : top.navigationController;
        KCLog(@"Back: %@", [nav popViewControllerAnimated:YES] ? @"popped" : @"nothing to pop");
        return YES;
    }
    return YES;
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    [[KCMediaProxy shared] ensureRunning];
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [KCSettings save];
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    KCLog(@"Memory warning");
    [[KCImageLoader shared] clearMemory];
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    [KCSettings save];
}

@end
