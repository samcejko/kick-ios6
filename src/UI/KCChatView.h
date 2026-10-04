#import <UIKit/UIKit.h>
#import "KCChatMessage.h"
#import "KCChatLayout.h"

@class KCChatView;

@protocol KCChatViewDelegate <NSObject>
@optional
- (void)chatView:(KCChatView *)chatView didTapName:(NSString *)slug displayName:(NSString *)displayName;
- (void)chatView:(KCChatView *)chatView didTapLink:(NSString *)url;
@end

// One chat line in the table
@interface KCChatCell : UITableViewCell
+ (NSString *)reuseIdentifier;
- (void)configureWithMessage:(KCChatMessage *)message layout:(KCChatLayout *)layout style:(KCChatStyle *)style alternate:(BOOL)alternate;
- (void)refreshImages;                 // an image arrived
@property (nonatomic, readonly, strong) KCChatMessage *message;
@property (nonatomic, readonly, strong) KCChatLayout *layout;
@end

// The chat of a channel, read only: the messages scroll with the newest at the bottom, a "new messages" button shows
// when the user scrolled up. Fed by KCChat (live) or the replay of a recording through -appendMessages:.
@interface KCChatView : UIView

@property (nonatomic, weak) id<KCChatViewDelegate> delegate;
@property (nonatomic, copy) NSString *channelId;
@property (nonatomic, copy) NSString *channelSlug;
@property (nonatomic) BOOL replayMode;                // a recording's chat (the lines carry their moment in the video)

- (void)appendMessages:(NSArray *)messages;           // KCChatMessage
- (void)appendNotice:(NSString *)text;
- (void)clearMessagesOfUser:(NSString *)slug seconds:(NSInteger)seconds;   // nil = everything
- (void)deleteMessageWithId:(NSString *)messageId;
- (void)removeAllMessages;
- (void)applyTheme;
- (void)scrollToBottom;

@end
