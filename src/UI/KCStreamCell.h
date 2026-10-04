#import <UIKit/UIKit.h>
#import "KCModels.h"

// A live stream in a grid: the "card" (thumbnail on top, texts below) on wide screens, a row (thumbnail on the left)
// on narrow ones. Also used for channels that are offline (the offline picture, no live badge).
@interface KCStreamCell : UICollectionViewCell
+ (NSString *)reuseIdentifier;
+ (CGFloat)rowHeightForWidth:(CGFloat)width;              // row layout (narrow)
+ (CGFloat)cardHeightForWidth:(CGFloat)width;             // card layout
- (void)configureWithStream:(KCStream *)stream asCard:(BOOL)card;
- (void)configureWithChannel:(KCChannel *)channel asCard:(BOOL)card;   // offline channel
- (void)applyTheme;
@end

// A category in a grid: its upright picture with the name and the viewer count below
@interface KCCategoryCell : UICollectionViewCell
+ (NSString *)reuseIdentifier;
+ (CGFloat)heightForWidth:(CGFloat)width;
- (void)configureWithCategory:(KCCategory *)category;
- (void)applyTheme;
@end

// A video or a clip in a list (table): thumbnail with the length, title, name/category, views and age
@interface KCVideoCell : UITableViewCell
+ (NSString *)reuseIdentifier;
+ (CGFloat)height;
- (void)configureWithVideo:(KCVideo *)video;
- (void)configureWithClip:(KCClip *)clip;
@end

// A channel in a list: round avatar, name, a live dot with the category or "offline"
@interface KCChannelCell : UITableViewCell
+ (NSString *)reuseIdentifier;
+ (CGFloat)height;
- (void)configureWithChannel:(KCChannel *)channel;
- (void)configureWithSlug:(NSString *)slug displayName:(NSString *)name avatarURL:(NSString *)avatar detail:(NSString *)detail;
@end
