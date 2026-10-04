#import "KCChatView.h"
#import "KCImageLoader.h"
#import "KCEmotes.h"
#import "KCSettings.h"
#import "KCTheme.h"
#import "KCUtils.h"
#import "KCCommon.h"
#import <QuartzCore/QuartzCore.h>

static const NSUInteger KCChatMaxMessages = 400;
static const NSUInteger KCChatTrimTo = 300;
static const CGFloat KCChatCellPadV = 4;
static const CGFloat KCChatCellPadH = 8;

#pragma mark - Line view

// Draws the text of one line; the images are UIImageViews above it
@interface KCChatLineView : UIView
@property (nonatomic, strong) KCChatLayout *layout;
@end

@implementation KCChatLineView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (void)setLayout:(KCChatLayout *)layout
{
    _layout = layout;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
    [self.layout drawInContext:UIGraphicsGetCurrentContext()];
}

@end

#pragma mark - Cell

@interface KCChatCell ()
@property (nonatomic, strong) KCChatMessage *message;
@property (nonatomic, strong) KCChatLayout *layout;
@property (nonatomic, strong) KCChatLineView *lineView;
@property (nonatomic, strong) NSMutableArray *imageViews;
@property (nonatomic, strong) UIView *separator;
@end

@implementation KCChatCell

+ (NSString *)reuseIdentifier { return @"chat"; }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _lineView = [[KCChatLineView alloc] initWithFrame:CGRectZero];
        [self.contentView addSubview:_lineView];
        _imageViews = [NSMutableArray array];
        _separator = [[UIView alloc] initWithFrame:CGRectZero];
        _separator.hidden = YES;
        [self.contentView addSubview:_separator];
    }
    return self;
}

- (void)configureWithMessage:(KCChatMessage *)message layout:(KCChatLayout *)layout style:(KCChatStyle *)style alternate:(BOOL)alternate
{
    KCTheme *t = [KCTheme shared];
    self.message = message;
    self.layout = layout;
    self.lineView.layout = layout;
    UIColor *background = [t chatBackgroundColor];
    if (message.kind == KCChatKindUserNotice) background = [t chatHighlightColor];
    else if (alternate) background = t.isDark ? [UIColor colorWithWhite:0.13 alpha:1] : [UIColor colorWithWhite:0.965 alpha:1];
    self.backgroundColor = background;
    self.contentView.backgroundColor = background;
    self.lineView.alpha = message.isDeleted ? 0.6 : 1.0;
    self.separator.hidden = ![KCSettings chatSeparators];
    self.separator.backgroundColor = [t chatSeparatorColor];
    [self refreshImages];
    [self setNeedsLayout];
}

- (void)refreshImages
{
    NSArray *slots = self.layout.imageSlots;
    while (self.imageViews.count < slots.count) {
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectZero];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:iv];
        [self.imageViews addObject:iv];
    }
    KCImageLoader *loader = [KCImageLoader shared];
    for (NSUInteger i = 0; i < self.imageViews.count; i++) {
        UIImageView *iv = self.imageViews[i];
        if (i >= slots.count) { iv.hidden = YES; iv.image = nil; continue; }
        KCChatImageSlot *slot = slots[i];
        iv.hidden = NO;
        iv.frame = CGRectOffset(slot.frame, KCChatCellPadH, KCChatCellPadV);
        UIImage *image = [loader imageForURL:slot.url];   // (starts the download when needed)
        if (image != iv.image) iv.image = image;
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    self.lineView.frame = CGRectMake(KCChatCellPadH, KCChatCellPadV, b.size.width - 2 * KCChatCellPadH, MAX(0, b.size.height - KCChatCellPadV));
    self.separator.frame = CGRectMake(0, b.size.height - 1, b.size.width, 1);
    [self refreshImages];
}

@end

#pragma mark - Chat view

@interface KCChatView () <UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *messages;
@property (nonatomic, strong) KCChatStyle *style;
@property (nonatomic, strong) UIButton *moreMessagesButton;
@property (nonatomic) BOOL stuckToBottom;
@property (nonatomic) NSUInteger unseen;
@property (nonatomic, strong) KCChatMessage *tappedMessage;
@property (nonatomic, copy) NSString *tappedLink;
@end

@implementation KCChatView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _messages = [NSMutableArray array];
        _stuckToBottom = YES;
        self.clipsToBounds = YES;

        _tableView = [[UITableView alloc] initWithFrame:self.bounds style:UITableViewStylePlain];
        _tableView.dataSource = self;
        _tableView.delegate = self;
        _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        _tableView.allowsSelection = NO;
        _tableView.scrollsToTop = NO;
        [_tableView registerClass:[KCChatCell class] forCellReuseIdentifier:[KCChatCell reuseIdentifier]];
        [self addSubview:_tableView];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tableTapped:)];
        tap.cancelsTouchesInView = NO;
        [_tableView addGestureRecognizer:tap];
        UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(tablePressed:)];
        press.minimumPressDuration = 0.5;
        [_tableView addGestureRecognizer:press];

        _moreMessagesButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _moreMessagesButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [_moreMessagesButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        [_moreMessagesButton addTarget:self action:@selector(moreMessagesTapped) forControlEvents:UIControlEventTouchUpInside];
        _moreMessagesButton.hidden = YES;
        [self addSubview:_moreMessagesButton];

        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(imageLoaded:) name:KCImageDidLoadNotification object:nil];
        [nc addObserver:self selector:@selector(emotesChanged) name:KCEmotesDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(settingsChanged) name:KCSettingsDidChangeNotification object:nil];
        [self applyTheme];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Theme and layout

- (void)applyTheme
{
    KCTheme *t = [KCTheme shared];
    self.backgroundColor = [t chatBackgroundColor];
    self.tableView.backgroundColor = [t chatBackgroundColor];
    self.tableView.indicatorStyle = t.isDark ? UIScrollViewIndicatorStyleWhite : UIScrollViewIndicatorStyleDefault;
    // (dark text on the bright green pill)
    [self.moreMessagesButton setBackgroundImage:[t pillImageWithColor:[t accentColor]] forState:UIControlStateNormal];
    [self invalidateLayouts];
}

- (void)settingsChanged
{
    [self invalidateLayouts];
}

- (void)emotesChanged
{
    // 7TV emotes arrived: lines that showed plain words are laid out again
    [self invalidateLayouts];
}

- (void)invalidateLayouts
{
    self.style = nil;
    for (KCChatMessage *m in self.messages) m.layout = nil;
    [self.tableView reloadData];
    if (self.stuckToBottom) [self scrollToBottom];
}

- (CGFloat)textWidth
{
    return self.tableView.bounds.size.width - 2 * KCChatCellPadH;
}

- (KCChatStyle *)currentStyle
{
    CGFloat width = [self textWidth];
    if (!self.style || fabs(self.style.width - width) > 0.5) self.style = [KCChatStyle currentStyleForWidth:width channelId:self.channelId];
    return self.style;
}

- (void)setChannelId:(NSString *)channelId
{
    _channelId = [channelId copy];
    self.style = nil;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect b = self.bounds;
    BOOL widthChanged = fabs(self.tableView.frame.size.width - b.size.width) > 0.5;
    if (!CGRectEqualToRect(self.tableView.frame, b)) self.tableView.frame = b;
    if (widthChanged) [self invalidateLayouts];
    CGSize pill = [self.moreMessagesButton.currentTitle sizeWithFont:self.moreMessagesButton.titleLabel.font];
    self.moreMessagesButton.frame = CGRectMake(floor((b.size.width - pill.width - 24) / 2), b.size.height - 32, pill.width + 24, 24);
}

#pragma mark - Messages

- (void)appendMessages:(NSArray *)messages
{
    if (!messages.count) return;
    KCChatStyle *style = [self currentStyle];
    for (KCChatMessage *m in messages) [KCChatLayout cachedLayoutForMessage:m style:style];
    [self.messages addObjectsFromArray:messages];
    if (self.messages.count > KCChatMaxMessages) {
        [self.messages removeObjectsInRange:NSMakeRange(0, self.messages.count - KCChatTrimTo)];
    }
    [self.tableView reloadData];
    if (self.stuckToBottom) {
        [self scrollToBottom];
    } else {
        // what the user is reading stays where it is (rows only come below it); the button counts the rest
        self.unseen += messages.count;
        [self updateNewMessagesButton];
    }
}

- (void)appendNotice:(NSString *)text
{
    [self appendMessages:@[ [KCChatMessage noticeWithText:text] ]];
}

- (void)clearMessagesOfUser:(NSString *)slug seconds:(NSInteger)seconds
{
    NSString *notice;
    if (!slug.length) {
        for (KCChatMessage *m in self.messages) if (m.kind == KCChatKindMessage) { m.isDeleted = YES; m.layout = nil; }
        notice = L(@"The chat was cleared by a moderator.");
    } else {
        NSString *name = slug;
        for (KCChatMessage *m in self.messages) {
            if (![m.slug isEqualToString:slug]) continue;
            m.isDeleted = YES;
            m.layout = nil;
            if (m.displayName.length) name = m.displayName;
        }
        if (seconds > 0) notice = [NSString stringWithFormat:L(@"%@ was timed out for %@."), name, [KCUtils formatDuration:seconds]];
        else notice = [NSString stringWithFormat:L(@"%@ was banned."), name];
    }
    [self appendNotice:notice];
}

- (void)deleteMessageWithId:(NSString *)messageId
{
    if (!messageId.length) return;
    for (KCChatMessage *m in self.messages) {
        if ([m.messageId isEqualToString:messageId]) { m.isDeleted = YES; m.layout = nil; }
    }
    [self.tableView reloadData];
}

- (void)removeAllMessages
{
    [self.messages removeAllObjects];
    self.unseen = 0;
    self.stuckToBottom = YES;
    [self.tableView reloadData];
    [self updateNewMessagesButton];
}

- (void)scrollToBottom
{
    NSInteger n = (NSInteger)self.messages.count;
    if (n <= 0) return;
    [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:n - 1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
    self.stuckToBottom = YES;
    self.unseen = 0;
    [self updateNewMessagesButton];
}

- (void)updateNewMessagesButton
{
    if (self.stuckToBottom || !self.unseen) {
        self.moreMessagesButton.hidden = YES;
        return;
    }
    [self.moreMessagesButton setTitle:[NSString stringWithFormat:L(@"%lu new messages ↓"), (unsigned long)self.unseen] forState:UIControlStateNormal];
    self.moreMessagesButton.hidden = NO;
    [self setNeedsLayout];
}

- (void)moreMessagesTapped
{
    [self scrollToBottom];
}

- (void)imageLoaded:(NSNotification *)note
{
    // the cell showing this image gets it; the others keep their layouts
    NSString *url = note.userInfo[@"url"];
    for (KCChatCell *cell in self.tableView.visibleCells) {
        for (KCChatImageSlot *slot in cell.layout.imageSlots) {
            if ([slot.url isEqualToString:url]) { [cell refreshImages]; break; }
        }
    }
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.messages.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    KCChatMessage *m = self.messages[(NSUInteger)indexPath.row];
    KCChatLayout *layout = [KCChatLayout cachedLayoutForMessage:m style:[self currentStyle]];
    return ceil(layout.height) + 2 * KCChatCellPadV;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    KCChatCell *cell = [tableView dequeueReusableCellWithIdentifier:[KCChatCell reuseIdentifier] forIndexPath:indexPath];
    KCChatMessage *m = self.messages[(NSUInteger)indexPath.row];
    KCChatStyle *style = [self currentStyle];
    [cell configureWithMessage:m layout:[KCChatLayout cachedLayoutForMessage:m style:style] style:style alternate:NO];
    return cell;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    CGFloat bottom = scrollView.contentOffset.y + scrollView.bounds.size.height;
    BOOL atBottom = bottom >= scrollView.contentSize.height - 30;
    if (atBottom != self.stuckToBottom) {
        self.stuckToBottom = atBottom;
        if (atBottom) self.unseen = 0;
        [self updateNewMessagesButton];
    }
}

#pragma mark - Taps

- (KCChatCell *)cellAtGesture:(UIGestureRecognizer *)gesture point:(CGPoint *)pointInCell
{
    CGPoint p = [gesture locationInView:self.tableView];
    NSIndexPath *ip = [self.tableView indexPathForRowAtPoint:p];
    if (!ip) return nil;
    KCChatCell *cell = (KCChatCell *)[self.tableView cellForRowAtIndexPath:ip];
    if (pointInCell) *pointInCell = [gesture locationInView:cell.contentView];
    return cell;
}

- (void)tableTapped:(UITapGestureRecognizer *)gesture
{
    CGPoint p;
    KCChatCell *cell = [self cellAtGesture:gesture point:&p];
    if (!cell || !cell.message.slug.length) return;
    CGPoint inLayout = CGPointMake(p.x - KCChatCellPadH, p.y - KCChatCellPadV);
    KCChatLink *link = [cell.layout linkAtPoint:inLayout];
    if (link) {
        self.tappedLink = link.url;
        self.tappedMessage = cell.message;
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:link.url delegate:self cancelButtonTitle:L(@"Cancel") destructiveButtonTitle:nil otherButtonTitles:L(@"Open Link"), L(@"Copy Link"), nil];
        sheet.tag = 2;
        [sheet showInView:self];
        return;
    }
    if ([cell.layout isNameAtPoint:inLayout]) {
        [self showActionsForMessage:cell.message];
    }
}

- (void)tablePressed:(UILongPressGestureRecognizer *)gesture
{
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    KCChatCell *cell = [self cellAtGesture:gesture point:NULL];
    if (!cell || !cell.message.slug.length) return;
    [self showActionsForMessage:cell.message];
}

- (void)showActionsForMessage:(KCChatMessage *)message
{
    self.tappedMessage = message;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:[message nameForDisplay] delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    [sheet addButtonWithTitle:L(@"Open Channel")];
    [sheet addButtonWithTitle:L(@"Copy Message")];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    sheet.tag = 1;
    [sheet showInView:self];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex < 0 || buttonIndex == actionSheet.cancelButtonIndex) return;
    KCChatMessage *m = self.tappedMessage;
    if (actionSheet.tag == 2) {
        if (buttonIndex == actionSheet.firstOtherButtonIndex) {
            if ([self.delegate respondsToSelector:@selector(chatView:didTapLink:)]) [self.delegate chatView:self didTapLink:self.tappedLink];
        } else {
            [UIPasteboard generalPasteboard].string = self.tappedLink ?: @"";
        }
        return;
    }
    if (buttonIndex == 0) {
        if ([self.delegate respondsToSelector:@selector(chatView:didTapName:displayName:)]) [self.delegate chatView:self didTapName:m.slug displayName:m.displayName];
    } else if (buttonIndex == 1) {
        [UIPasteboard generalPasteboard].string = m.text.length ? m.text : (m.systemText ?: @"");
    }
}

@end
