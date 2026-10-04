#import <UIKit/UIKit.h>

// Colours, fonts and the code-drawn glossy iOS 6 artwork: the dark house look (near black, bright green) and a
// light one. Posts KCThemeDidChangeNotification when the theme changes.
@interface KCTheme : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL isDark;
- (void)setDark:(BOOL)dark;                 // persists, posts the notification, updates the status bar
- (void)invalidateArtwork;                  // after a settings change that affects drawing

// Colours
- (UIColor *)backgroundColor;               // behind lists and grids
- (UIColor *)cardColor;                     // list rows, cards
- (UIColor *)primaryTextColor;
- (UIColor *)secondaryTextColor;
- (UIColor *)separatorColor;
- (UIColor *)accentColor;                   // the green
- (UIColor *)liveColor;                     // the green of the LIVE badge (black lettering on it)
- (UIColor *)linkColor;
- (UIColor *)chatBackgroundColor;
- (UIColor *)chatTextColor;
- (UIColor *)chatSystemTextColor;
- (UIColor *)chatHighlightColor;            // behind subscriptions, gifts, hosts
- (UIColor *)chatDeletedTextColor;
- (UIColor *)chatSeparatorColor;
- (UIColor *)switchTintColor;               // UISwitch when on
- (UIColor *)playerBackgroundColor;

// Artwork (stretchable where it makes sense)
- (UIImage *)cardBackgroundImage;           // white glossy card with a hairline and a soft bottom shadow
- (UIImage *)cardBackgroundImageHighlighted;
- (UIImage *)pillImageWithColor:(UIColor *)color;    // small glossy capsule (LIVE, viewer counts)
- (UIImage *)darkPillImage;                 // translucent black capsule for text over thumbnails
- (UIImage *)buttonImageHighlighted:(BOOL)highlighted;              // grey glossy button
- (UIImage *)accentButtonImageHighlighted:(BOOL)highlighted disabled:(BOOL)disabled;   // green glossy button
- (UIImage *)thumbnailPlaceholder;          // dark 16:9 box with a faint play sign
- (UIImage *)categoryPlaceholder;
- (UIImage *)avatarPlaceholderWithSize:(CGFloat)size;
- (UIImage *)sectionHeaderBackgroundImage;  // the blue-grey gradient of plain table headers
- (UIImage *)controlsGradientImageTop:(BOOL)top;      // black fade behind the player controls

// Icons (template-like alpha drawings): tab bar
- (UIImage *)tabIconFavorites;
- (UIImage *)tabIconBrowse;
- (UIImage *)tabIconCategories;
- (UIImage *)tabIconSearch;
- (UIImage *)tabIconSettings;
// player controls, drawn in white
- (UIImage *)playIcon;
- (UIImage *)pauseIcon;
- (UIImage *)fullscreenIconEnter:(BOOL)enter;
- (UIImage *)chatIconOn:(BOOL)on;
- (UIImage *)gearIconWhite;
- (UIImage *)closeIconWhite;
- (UIImage *)backChevronWhite;
- (UIImage *)replayIcon;                    // circular arrow, for a stream that ended
- (UIImage *)skipIconForward:(BOOL)forward;
// misc
- (UIImage *)starIconFilled:(BOOL)filled color:(UIColor *)color size:(CGFloat)size;
- (UIImage *)liveDotImage;
- (UIImage *)checkmarkImage;
- (UIImage *)disclosureChevronImage;        // grey chevron for custom cells

// Fonts
- (UIFont *)titleFont;                      // bold 15/17
- (UIFont *)bodyFont;
- (UIFont *)smallFont;
- (UIFont *)tinyBoldFont;
- (CGFloat)chatFontSize;                    // from the settings
- (UIFont *)chatFont;
- (UIFont *)chatBoldFont;
- (UIFont *)chatSmallFont;

// Applying to UIKit
- (UIBarStyle)barStyle;
- (UIStatusBarStyle)statusBarStyle;
- (void)applyToNavigationBar:(UINavigationBar *)bar;
- (void)applyToToolbar:(UIToolbar *)bar;
- (void)applyToTabBar:(UITabBar *)bar;
- (void)applyToTableView:(UITableView *)tableView;
- (void)styleCell:(UITableViewCell *)cell;
- (void)applyToSearchBar:(UISearchBar *)bar;
- (UIActivityIndicatorViewStyle)spinnerStyle;

@end
