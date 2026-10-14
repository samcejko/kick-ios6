#import "KCExternalOpen.h"
#import "KCLinks.h"
#import "KCNavigator.h"
#import "KCModern.h"
#import "KCUtils.h"
#import "KCCommon.h"

typedef NS_ENUM(NSInteger, KCOpenAction) {
    KCOpenActionSafari = 1,     // the system's browser
    KCOpenActionSurfari,        // surfari://open?url= (iOS 6)
    KCOpenActionSister,         // tubie:open?url=, twitcher:open?url=, tiktak:open?url=
    KCOpenActionCopy,
    KCOpenActionShare,          // the system share sheet (iOS 7 and newer)
    KCOpenActionLink,           // one of several addresses in a text: the tapped-link code path
};

// One button of a sheet (plain objects, no blocks: see the note on blocks in KCChat)
@interface KCOpenChoice : NSObject
@property (nonatomic) KCOpenAction action;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSURL *url;       // what the button opens, copies or shares
+ (instancetype)choice:(KCOpenAction)action title:(NSString *)title url:(NSURL *)url;
@end

@implementation KCOpenChoice
+ (instancetype)choice:(KCOpenAction)action title:(NSString *)title url:(NSURL *)url
{
    KCOpenChoice *c = [[KCOpenChoice alloc] init];
    c.action = action;
    c.title = title;
    c.url = url;
    return c;
}
@end

@interface KCExternalOpen () <UIActionSheetDelegate>
@property (nonatomic, strong) NSArray *choices;                 // KCOpenChoice, in the order of the buttons
@property (nonatomic, weak) UIViewController *controller;
@property (nonatomic, weak) UIView *anchor;
@end

// The live sheets' delegates, so ARC does not free them while the sheet is on screen
static NSMutableArray *g_live;

// The sister apps of this family (same author, same look) and the sites they show. Their URL schemes take an
// address the way kicker:open?url= does; TikTak still answers to its old name.
static NSArray *KCSisterApps(void)
{
    static NSArray *apps;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        apps = @[ @{ @"name": @"Tubie", @"title": @"Open in Tubie", @"schemes": @[ @"tubie" ], @"hosts": @[ @"youtube.com", @"youtu.be" ] },
                  @{ @"name": @"Twitcher", @"title": @"Open in Twitcher", @"schemes": @[ @"twitcher" ], @"hosts": @[ @"twitch.tv" ] },
                  @{ @"name": @"TikTak", @"title": @"Open in TikTak", @"schemes": @[ @"tiktak", @"tikie" ], @"hosts": @[ @"tiktok.com" ] } ];
    });
    return apps;
}

static BOOL KCHostIsUnder(NSString *host, NSString *domain)
{
    return [host isEqualToString:domain] || [host hasSuffix:[@"." stringByAppendingString:domain]];
}

@implementation KCExternalOpen

#pragma mark - Other apps

+ (BOOL)surfariAvailable
{
    return [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"surfari://open"]];
}

+ (NSURL *)surfariURLForURL:(NSURL *)url
{
    NSString *encoded = [KCUtils urlEncode:url.absoluteString ?: @""];
    return [NSURL URLWithString:[@"surfari://open?url=" stringByAppendingString:encoded]];
}

// The sister app for an address, with the scheme it answers to ("scheme"), or nil
+ (NSDictionary *)sisterAppForURL:(NSURL *)url
{
    NSString *host = [url.host lowercaseString];
    if (!host.length) return nil;
    UIApplication *app = [UIApplication sharedApplication];
    for (NSDictionary *sister in KCSisterApps()) {
        BOOL match = NO;
        for (NSString *domain in sister[@"hosts"]) if (KCHostIsUnder(host, domain)) match = YES;
        if (!match) continue;
        // (iOS 9 and newer answer only for the schemes in LSApplicationQueriesSchemes of Info.plist)
        for (NSString *scheme in sister[@"schemes"]) {
            if ([app canOpenURL:[NSURL URLWithString:[scheme stringByAppendingString:@":open"]]]) {
                NSMutableDictionary *found = [sister mutableCopy];
                found[@"scheme"] = scheme;
                return found;
            }
        }
        return nil;
    }
    return nil;
}

+ (NSString *)sisterAppNameForURL:(NSURL *)url
{
    return [self sisterAppForURL:url][@"name"];
}

+ (NSURL *)sisterURLWithScheme:(NSString *)scheme forURL:(NSURL *)url
{
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@:open?url=%@", scheme, [KCUtils urlEncode:url.absoluteString ?: @""]]];
}

#pragma mark - Tapped links

+ (void)openLink:(NSString *)link from:(UIViewController *)controller anchor:(UIView *)anchor
{
    [self openLinkURL:[KCLinks URLForLinkText:link] from:controller anchor:anchor];
}

+ (void)openLinkURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor
{
    if (!url) return;
    // kick.com: the channel page inside the app (the same as kicker:open?url=)
    if ([KCNavigator openKickURL:url from:controller]) return;
    [self presentOpenInForURL:url from:controller anchor:anchor];
}

+ (void)openLinks:(NSArray *)links from:(UIViewController *)controller anchor:(UIView *)anchor
{
    if (!links.count) return;
    if (links.count == 1) { [self openLink:links[0] from:controller anchor:anchor]; return; }
    NSMutableArray *choices = [NSMutableArray array];
    for (NSString *link in links) {
        NSURL *url = [KCLinks URLForLinkText:link];
        if (url) [choices addObject:[KCOpenChoice choice:KCOpenActionLink title:[KCLinks displayTextForURL:url] url:url]];
    }
    if (choices.count == 1) { [self openLinkURL:[(KCOpenChoice *)choices[0] url] from:controller anchor:anchor]; return; }
    if (choices.count) [self presentChoices:choices title:L(@"Links") from:controller anchor:anchor];
}

#pragma mark - The chooser

+ (void)presentShareSheetForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor
{
    [self present:url share:YES from:controller anchor:anchor];
}

+ (void)presentOpenInForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor
{
    [self present:url share:NO from:controller anchor:anchor];
}

+ (void)present:(NSURL *)url share:(BOOL)share from:(UIViewController *)controller anchor:(UIView *)anchor
{
    if (!url || ![[url.scheme lowercaseString] hasPrefix:@"http"]) return;
    NSMutableArray *choices = [NSMutableArray array];
    // a sister app for the site comes first, on every iOS
    NSDictionary *sister = [self sisterAppForURL:url];
    if (sister) [choices addObject:[KCOpenChoice choice:KCOpenActionSister title:L(sister[@"title"]) url:[self sisterURLWithScheme:sister[@"scheme"] forURL:url]]];
    if (KCModernIOS()) {
        // iOS 7 and newer: no chooser of browsers. Safari straight away, the system's sheet for sharing; a sheet of
        // our own only when a sister app could open the address.
        if (!sister) {
            if (share) [self presentActivitySheetForURL:url from:controller anchor:anchor];
            else [[UIApplication sharedApplication] openURL:url];
            return;
        }
        if (share) [choices addObject:[KCOpenChoice choice:KCOpenActionShare title:L(@"Share…") url:url]];
        else [choices addObject:[KCOpenChoice choice:KCOpenActionSafari title:L(@"Open in Safari") url:url]];
    } else {
        // iOS 6: Safari, or Surfari (the iOS 6 browser of this family) when installed; "Copy link" when sharing
        if (share) [choices addObject:[KCOpenChoice choice:KCOpenActionCopy title:L(@"Copy link") url:url]];
        [choices addObject:[KCOpenChoice choice:KCOpenActionSafari title:L(@"Open in Safari") url:url]];
        if ([self surfariAvailable]) [choices addObject:[KCOpenChoice choice:KCOpenActionSurfari title:L(@"Open in Surfari") url:[self surfariURLForURL:url]]];
    }
    [self presentChoices:choices title:url.absoluteString from:controller anchor:anchor];
}

+ (void)presentChoices:(NSArray *)choices title:(NSString *)title from:(UIViewController *)controller anchor:(UIView *)anchor
{
    KCExternalOpen *open = [[KCExternalOpen alloc] init];
    open.choices = choices;
    open.controller = controller;
    open.anchor = anchor;
    if (!g_live) g_live = [NSMutableArray array];
    [g_live addObject:open];

    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:title delegate:open cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    for (KCOpenChoice *c in choices) [sheet addButtonWithTitle:c.title];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    UIView *view = controller.view ?: [KCNavigator presenterFrom:nil].view;
    if (KCIsPad() && anchor && anchor.window) [sheet showFromRect:anchor.bounds inView:anchor animated:YES];
    else [sheet showInView:view];
}

// (acted on once the sheet is gone: what follows may be another sheet or the share sheet)
- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (buttonIndex >= 0 && buttonIndex != actionSheet.cancelButtonIndex && (NSUInteger)buttonIndex < self.choices.count) {
        [self perform:self.choices[(NSUInteger)buttonIndex]];
    }
    [g_live removeObject:self];
}

- (void)perform:(KCOpenChoice *)choice
{
    switch (choice.action) {
        case KCOpenActionSafari:
        case KCOpenActionSurfari:
        case KCOpenActionSister:
            [[UIApplication sharedApplication] openURL:choice.url];
            break;
        case KCOpenActionCopy:
            [UIPasteboard generalPasteboard].string = choice.url.absoluteString ?: @"";
            break;
        case KCOpenActionShare:
            [KCExternalOpen presentActivitySheetForURL:choice.url from:self.controller anchor:self.anchor];
            break;
        case KCOpenActionLink:
            [KCExternalOpen openLinkURL:choice.url from:self.controller anchor:self.anchor];
            break;
    }
}

#pragma mark - The system share sheet (iOS 7 and newer)

+ (void)presentActivitySheetForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor
{
    UIViewController *presenter = controller ?: [KCNavigator presenterFrom:nil];
    if (!presenter) return;
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[ url ] applicationActivities:nil];
    if (KCIsPad()) {
        // the iPad shows it in a popover: from the anchor, or from the middle of the view without one (iOS 8 and
        // newer; the one iOS 7 iPad shows it as a sheet). Newer than iOS 6, hence the pragma and the check.
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
        if ([activity respondsToSelector:@selector(popoverPresentationController)]) {
            UIPopoverPresentationController *popover = activity.popoverPresentationController;
            UIView *source = (anchor && anchor.window) ? anchor : presenter.view;
            popover.sourceView = source;
            if (source == anchor) {
                popover.sourceRect = anchor.bounds;
            } else {
                CGRect b = presenter.view.bounds;
                popover.sourceRect = CGRectMake(floor(CGRectGetMidX(b)), floor(CGRectGetMidY(b)), 1, 1);
                popover.permittedArrowDirections = 0;
            }
        }
#pragma clang diagnostic pop
#endif
    }
    [presenter presentViewController:activity animated:YES completion:nil];
}

@end
