#import <UIKit/UIKit.h>

// Web links leaving the app's own pages. A kick.com address opens inside Kicker (the channel page); an address of
// YouTube, Twitch or TikTok is offered to the sister app of this family (Tubie, Twitcher, TikTak) when it is
// installed; everything else goes to a browser. On iOS 6 the browser is chosen in an action sheet (Safari, or
// Surfari when installed); iOS 7 and newer open Safari straight away and share through the system's share sheet,
// so a sheet appears there only when a sister app could open the address. Retains itself until the sheet is gone.
@interface KCExternalOpen : NSObject

// A link tapped in a text (a chat line, a title, a bio): the one code path every tapped link runs. `link` is the
// address as written ("kick.com/xqc", "www.…", "https://…").
+ (void)openLink:(NSString *)link from:(UIViewController *)controller anchor:(UIView *)anchor;
+ (void)openLinkURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor;
// The links of one text: a single one opens, several are listed in a sheet first
+ (void)openLinks:(NSArray *)links from:(UIViewController *)controller anchor:(UIView *)anchor;

// Just the browser chooser (no "copy"); used where a link is being opened rather than shared
+ (void)presentOpenInForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor;
// Sharing: iOS 6 the chooser with "Copy link"; iOS 7 and newer the system share sheet (UIActivityViewController)
+ (void)presentShareSheetForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor;

+ (BOOL)surfariAvailable;
// The sister app that shows this address ("Tubie", "Twitcher", "TikTak"), or nil: not one of their sites, or not installed
+ (NSString *)sisterAppNameForURL:(NSURL *)url;

@end
