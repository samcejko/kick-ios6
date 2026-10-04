#import "KCNavigator.h"
#import "KCPlayerViewController.h"
#import "KCChannelViewController.h"
#import "KCCategoryViewController.h"
#import "KCCommon.h"

@implementation KCNavigator

+ (UIViewController *)presenterFrom:(UIViewController *)controller
{
    UIViewController *top = controller ?: [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    return top;
}

// The player somewhere in the chain of presented screens (a channel page may lie over it), nil when none
+ (KCPlayerViewController *)activePlayer
{
    UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (vc) {
        if ([vc isKindOfClass:[KCPlayerViewController class]] && !vc.isBeingDismissed) return (KCPlayerViewController *)vc;
        vc = vc.presentedViewController;
    }
    return nil;
}

+ (void)presentPlayer:(KCPlayerViewController *)player from:(UIViewController *)controller
{
    KCPlayerViewController *current = [self activePlayer];
    if (current) {
        // already watching something (maybe under a channel page): the new content takes its place, never a second
        // player playing alongside
        [current replaceWithPlayer:player];
        return;
    }
    UIViewController *presenter = [self presenterFrom:controller];
    player.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [presenter presentViewController:player animated:YES completion:nil];
}

+ (void)openStream:(KCStream *)stream from:(UIViewController *)controller
{
    if (!stream.slug.length) return;
    KCPlayerViewController *player = [[KCPlayerViewController alloc] initWithChannelSlug:stream.slug stream:stream];
    [self presentPlayer:player from:controller];
}

+ (void)watchChannelSlug:(NSString *)slug from:(UIViewController *)controller
{
    if (!slug.length) return;
    KCPlayerViewController *player = [[KCPlayerViewController alloc] initWithChannelSlug:slug stream:nil];
    [self presentPlayer:player from:controller];
}

+ (void)openVideo:(KCVideo *)video from:(UIViewController *)controller
{
    if (!video.sourceURL.length) return;
    KCPlayerViewController *player = [[KCPlayerViewController alloc] initWithVideo:video];
    [self presentPlayer:player from:controller];
}

+ (void)openClip:(KCClip *)clip from:(UIViewController *)controller
{
    if (!clip.playlistURL.length) return;
    KCPlayerViewController *player = [[KCPlayerViewController alloc] initWithClip:clip];
    [self presentPlayer:player from:controller];
}

+ (UINavigationController *)navigationControllerFrom:(UIViewController *)controller
{
    UIViewController *presenter = [self presenterFrom:controller];
    if ([presenter isKindOfClass:[UINavigationController class]]) return (UINavigationController *)presenter;
    if (presenter.navigationController) return presenter.navigationController;
    if ([presenter isKindOfClass:[UITabBarController class]]) {
        UIViewController *selected = [(UITabBarController *)presenter selectedViewController];
        if ([selected isKindOfClass:[UINavigationController class]]) return (UINavigationController *)selected;
    }
    return nil;
}

+ (void)openChannelSlug:(NSString *)slug from:(UIViewController *)controller
{
    if (!slug.length) return;
    KCChannelViewController *vc = [[KCChannelViewController alloc] initWithSlug:slug];
    UIViewController *presenter = [self presenterFrom:controller];
    if ([presenter isKindOfClass:[KCPlayerViewController class]]) {
        // from the player: the channel page opens in its own stack over the video
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        vc.showsDoneButton = YES;
        nav.modalPresentationStyle = KCIsPad() ? UIModalPresentationFormSheet : UIModalPresentationFullScreen;
        [presenter presentViewController:nav animated:YES completion:nil];
        return;
    }
    UINavigationController *nav = [self navigationControllerFrom:controller];
    if (nav) [nav pushViewController:vc animated:YES];
}

+ (void)openCategory:(KCCategory *)category from:(UIViewController *)controller
{
    if (!category) return;
    KCCategoryViewController *vc = [[KCCategoryViewController alloc] initWithCategory:category];
    UINavigationController *nav = [self navigationControllerFrom:controller];
    if (nav) [nav pushViewController:vc animated:YES];
}

@end
