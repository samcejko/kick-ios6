#import "KCPlayerViewController.h"
#import "KCPlayerView.h"
#import "KCChatView.h"
#import "KCPlayback.h"
#import "KCMediaProxy.h"
#import "KCAPI.h"
#import "KCChat.h"
#import "KCEmotes.h"
#import "KCFavorites.h"
#import "KCNavigator.h"
#import "KCExternalOpen.h"
#import "KCSettings.h"
#import "KCTheme.h"
#import "KCUtils.h"
#import "KCCommon.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MPNowPlayingInfoCenter.h>
#import <MediaPlayer/MPMediaItem.h>

typedef NS_ENUM(NSInteger, KCPlayerMode) {
    KCPlayerModeLive = 0,
    KCPlayerModeVideo,
    KCPlayerModeClip,
};

static void *KCStatusContext = &KCStatusContext;
static void *KCBufferEmptyContext = &KCBufferEmptyContext;
static void *KCKeepUpContext = &KCKeepUpContext;
static const NSTimeInterval KCStallReloadAfter = 20;      // seconds without progress while playing
static const NSInteger KCMaxAutomaticReloads = 3;
static const NSTimeInterval KCInfoRefreshInterval = 60;
static const NSTimeInterval KCLivePauseReloadAfter = 40;   // paused this long: back to the live edge with a fresh playlist
static const NSTimeInterval KCHistoryWait = 6;             // live messages wait at most this long for the history
static const NSTimeInterval KCReplayWindow = 5;            // what one request of the chat history covers
static const NSTimeInterval KCReplayLead = 20;             // the replay is fetched this far ahead of the picture

@interface KCPlayerViewController () <KCPlayerViewDelegate, KCChatViewDelegate, KCChatDelegate, UIActionSheetDelegate>
@property (nonatomic) KCPlayerMode mode;
@property (nonatomic, copy) NSString *slug;
@property (nonatomic, strong) KCStream *stream;
@property (nonatomic, strong) KCVideo *video;
@property (nonatomic, strong) KCClip *clip;
@property (nonatomic, strong) KCChannel *channel;
@property (nonatomic, copy) NSString *channelId;
// playback
@property (nonatomic, strong) NSArray *variants;          // KCVariant
@property (nonatomic, strong) KCVariant *currentVariant;  // nil = automatic
@property (nonatomic, copy) NSString *quality;            // the preference in use
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *item;
@property (nonatomic, strong) KCHTTPTask *loadTask;
@property (nonatomic, strong) KCHTTPTask *infoTask;
@property (nonatomic, strong) NSTimer *tickTimer;
@property (nonatomic) BOOL wantsToPlay;
@property (nonatomic) BOOL itemReady;
@property (nonatomic) BOOL ended;
@property (nonatomic) NSInteger automaticReloads;
@property (nonatomic) NSTimeInterval lastProgressTime;    // wall clock of the last change of the playback position
@property (nonatomic) double lastPosition;
@property (nonatomic) NSTimeInterval pausedAt;
@property (nonatomic) NSTimeInterval lastInfoRefresh;
@property (nonatomic) NSUInteger proxyGeneration;
@property (nonatomic) BOOL inBackground;
@property (nonatomic) double pendingSeek;                 // seconds to seek to once the item is ready (-1 = none)
// views
@property (nonatomic, strong) KCPlayerView *playerView;
@property (nonatomic, strong) KCChatView *chatView;
@property (nonatomic) BOOL fullscreen;
@property (nonatomic) BOOL chatVisible;
// live chat
@property (nonatomic, strong) KCChat *chat;
@property (nonatomic, strong) KCHTTPTask *historyTask;
@property (nonatomic, strong) NSMutableArray *heldMessages;    // live lines waiting for the history (nil = none wait)
@property (nonatomic, copy) NSString *roomModes;               // the chat modes announced last
// chat replay (recordings)
@property (nonatomic, strong) NSMutableArray *replayQueue;     // messages waiting for their moment (replayOffset)
@property (nonatomic, strong) NSMutableSet *replaySeen;        // ids of the last window (a line on the border comes twice)
@property (nonatomic) double replayFetchedUpTo;                // the history is known up to this offset (-1 = not yet)
@property (nonatomic) NSTimeInterval replayRetryAt;            // after a failed request: not before this
@property (nonatomic, strong) KCHTTPTask *replayTask;
@end

@implementation KCPlayerViewController

#pragma mark - Init

- (instancetype)initCommon
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.wantsFullScreenLayout = YES;
        _quality = [KCSettings preferredQuality];
        _chatVisible = [KCSettings showChat];
        _replayQueue = [NSMutableArray array];
        _replaySeen = [NSMutableSet set];
        _replayFetchedUpTo = -1;
        _pendingSeek = -1;
        _wantsToPlay = YES;
    }
    return self;
}

- (instancetype)initWithChannelSlug:(NSString *)slug stream:(KCStream *)stream
{
    self = [self initCommon];
    if (self) {
        _mode = KCPlayerModeLive;
        _slug = [slug lowercaseString];
        _stream = stream;
        _channelId = stream.userId;
    }
    return self;
}

- (instancetype)initWithVideo:(KCVideo *)video
{
    self = [self initCommon];
    if (self) {
        _mode = KCPlayerModeVideo;
        _video = video;
        _slug = video.ownerSlug;
        _channelId = video.channelId;
    }
    return self;
}

- (instancetype)initWithClip:(KCClip *)clip
{
    self = [self initCommon];
    if (self) {
        _mode = KCPlayerModeClip;
        _clip = clip;
        _slug = clip.broadcasterSlug;
    }
    return self;
}

- (void)dealloc
{
    [self teardownPlayback];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - View

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.playerView = [[KCPlayerView alloc] initWithFrame:self.view.bounds];
    self.playerView.delegate = self;
    self.playerView.isLive = self.mode == KCPlayerModeLive;
    self.playerView.chatButtonHidden = self.mode == KCPlayerModeClip;
    [self.view addSubview:self.playerView];

    if (self.mode != KCPlayerModeClip) {
        self.chatView = [[KCChatView alloc] initWithFrame:CGRectZero];
        self.chatView.delegate = self;
        self.chatView.channelId = self.channelId;
        self.chatView.channelSlug = self.slug;
        self.chatView.replayMode = self.mode == KCPlayerModeVideo;
        [self.view addSubview:self.chatView];
    } else {
        self.chatVisible = NO;
    }
    self.playerView.chatVisible = self.chatVisible;
    [self updateTitles];

    NSError *audioError = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&audioError];
    [[AVAudioSession sharedInstance] setActive:YES error:NULL];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(didEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(willEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
    [nc addObserver:self selector:@selector(themeChanged) name:KCThemeDidChangeNotification object:nil];

    self.playerView.closeIsBack = NO;
    self.playerView.qualityTitle = L(@"Quality");
    if (self.mode != KCPlayerModeClip) [[KCEmoteStore shared] loadGlobalsIfNeeded];
    // (live: the channel comes along with the playlist; a recording looks it up for the channel's emotes)
    [self startPlayback];
    if (self.mode == KCPlayerModeVideo) {
        [self refreshInfo];
        [self startReplay];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self updateStatusBar];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self becomeFirstResponder];
    if (!self.tickTimer) self.tickTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [self updateIdleTimer];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.tickTimer invalidate];
    self.tickTimer = nil;
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationNone];
    [[UIApplication sharedApplication] setStatusBarStyle:[[KCTheme shared] statusBarStyle] animated:NO];
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (void)updateStatusBar
{
    UIApplication *app = [UIApplication sharedApplication];
    BOOL hide = self.fullscreen || (!KCIsPad() && UIInterfaceOrientationIsLandscape(self.interfaceOrientation));
    [app setStatusBarHidden:hide withAnimation:UIStatusBarAnimationFade];
    if (!hide) [app setStatusBarStyle:UIStatusBarStyleBlackOpaque animated:NO];
    self.playerView.topInset = hide ? 0 : 20;
    [self.view setNeedsLayout];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGRect b = self.view.bounds;
    BOOL showChat = self.chatVisible && self.chatView && !self.fullscreen;
    self.chatView.hidden = !showChat;
    if (!showChat) {
        self.playerView.frame = b;
        return;
    }
    BOOL landscape = b.size.width > b.size.height;
    CGFloat top = self.playerView.topInset;   // (the status bar, when it shows)
    if (landscape) {
        CGFloat chatW = KCIsPad() ? 340 : 190;
        self.playerView.frame = CGRectMake(0, 0, b.size.width - chatW, b.size.height);
        self.chatView.frame = CGRectMake(b.size.width - chatW, top, chatW, b.size.height - top);
    } else {
        CGFloat videoH = floor(b.size.width * 9.0 / 16.0) + top;
        if (KCIsPad()) videoH = MAX(videoH, floor(b.size.height * 0.5));
        self.playerView.frame = CGRectMake(0, 0, b.size.width, videoH);
        self.chatView.frame = CGRectMake(0, videoH, b.size.width, b.size.height - videoH);
    }
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [super willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
    UIApplication *app = [UIApplication sharedApplication];
    BOOL hide = self.fullscreen || (!KCIsPad() && UIInterfaceOrientationIsLandscape(toInterfaceOrientation));
    [app setStatusBarHidden:hide withAnimation:UIStatusBarAnimationNone];
    self.playerView.topInset = hide ? 0 : 20;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

- (BOOL)shouldAutorotate
{
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return KCIsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;
}

- (void)themeChanged
{
    [self.chatView applyTheme];
}

- (void)updateIdleTimer
{
    [UIApplication sharedApplication].idleTimerDisabled = [KCSettings keepScreenOn] && self.wantsToPlay && !self.ended;
}

#pragma mark - Titles and info

- (NSString *)channelName
{
    return self.channel.displayName ?: (self.stream.displayName ?: (self.video.ownerName ?: (self.clip.broadcasterName ?: self.slug)));
}

- (void)updateTitles
{
    NSString *title = nil, *category = nil;
    switch (self.mode) {
        case KCPlayerModeLive:
            title = self.stream.title.length ? self.stream.title : [self channelName];
            category = self.stream.categoryName;
            break;
        case KCPlayerModeVideo:
            title = self.video.title.length ? self.video.title : L(@"Video");
            category = self.video.categoryName;
            break;
        case KCPlayerModeClip:
            title = self.clip.title.length ? self.clip.title : L(@"Clip");
            category = self.clip.categoryName;
            break;
    }
    NSString *name = [self channelName];
    self.playerView.title = title;
    self.playerView.subtitle = category.length ? [NSString stringWithFormat:@"%@ · %@", name, category] : name;
    [self updateStatusText];
    [self updateNowPlaying];
}

- (void)updateStatusText
{
    if (self.mode != KCPlayerModeLive) return;
    NSMutableArray *parts = [NSMutableArray array];
    if (self.stream.viewers > 0) [parts addObject:[KCUtils formatViewers:self.stream.viewers]];
    if (self.stream.startedAt) [parts addObject:[KCUtils formatUptimeSince:self.stream.startedAt]];
    self.playerView.statusText = [parts componentsJoinedByString:@" · "];
}

- (void)updateNowPlaying
{
    Class center = NSClassFromString(@"MPNowPlayingInfoCenter");
    if (!center) return;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (self.playerView.title.length) info[MPMediaItemPropertyTitle] = self.playerView.title;
    NSString *artist = [self channelName];
    if (artist.length) info[MPMediaItemPropertyArtist] = artist;
    NSString *category = self.stream.categoryName ?: (self.video.categoryName ?: self.clip.categoryName);
    if (category.length) info[MPMediaItemPropertyAlbumTitle] = category;
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
}

// The channel again: the stream's title, category and viewers now and then while live, the emotes of a recording
- (void)refreshInfo
{
    if (self.mode == KCPlayerModeClip || self.infoTask || !self.slug.length) return;
    self.lastInfoRefresh = [NSDate timeIntervalSinceReferenceDate];
    __weak KCPlayerViewController *weakSelf = self;
    self.infoTask = [KCAPI channel:self.slug completion:^(KCChannel *channel, NSError *error) {
        KCPlayerViewController *s = weakSelf;
        if (!s) return;
        s.infoTask = nil;
        if (channel) [s adoptChannel:channel];
    }];
}

- (void)adoptChannel:(KCChannel *)channel
{
    self.channel = channel;
    self.lastInfoRefresh = [NSDate timeIntervalSinceReferenceDate];
    [[KCFavorites shared] rememberChannel:channel];
    if (self.mode == KCPlayerModeLive && channel.stream) self.stream = channel.stream;
    if (channel.userId.length && ![channel.userId isEqualToString:self.channelId]) {
        self.channelId = channel.userId;
        self.chatView.channelId = channel.userId;
    }
    if (self.mode != KCPlayerModeClip) [[KCEmoteStore shared] loadChannel:channel.userId account:channel.accountId];
    if (self.mode == KCPlayerModeLive) [self startChatIfNeeded];
    [self updateTitles];
}

#pragma mark - Playback

- (void)startPlayback
{
    [self.loadTask cancel];
    self.ended = NO;
    self.itemReady = NO;
    [self.playerView showMessage:nil retryTitle:nil];
    self.playerView.controlsLocked = NO;
    [self.playerView setBuffering:YES];
    __weak KCPlayerViewController *weakSelf = self;
    void (^play)(NSArray *, NSError *) = ^(NSArray *variants, NSError *error) {
        KCPlayerViewController *s = weakSelf;
        if (!s) return;
        s.loadTask = nil;
        if (error) { [s failWithError:error]; return; }
        s.variants = variants;
        if (s.mode == KCPlayerModeVideo && s.pendingSeek < 0) {
            NSTimeInterval resume = [KCSettings resumePositionForVideo:s.video.videoId];
            if (resume > 10 && resume < s.video.length - 30) s.pendingSeek = resume;
        }
        [s playVariants];
    };
    // (each case in braces: a block literal lives to the end of its scope, and no case may jump into that)
    switch (self.mode) {
        case KCPlayerModeLive: {
            // (a fresh look at the channel each time: its playback URL carries a token that does not last forever)
            self.loadTask = [KCPlayback variantsForChannel:self.slug completion:^(NSArray *variants, KCChannel *channel, NSError *error) {
                KCPlayerViewController *s = weakSelf;
                if (s && channel) [s adoptChannel:channel];
                play(variants, error);
            }];
            break;
        }
        case KCPlayerModeVideo: {
            self.loadTask = [KCPlayback variantsForVideo:self.video completion:play];
            break;
        }
        case KCPlayerModeClip: {
            self.loadTask = [KCPlayback variantsForClip:self.clip completion:play];
            break;
        }
    }
}

- (void)playVariants
{
    KCVariant *chosen = nil;
    NSURL *url = [KCPlayback playerURLForVariants:self.variants quality:self.quality chosen:&chosen];
    if (!url) {
        [self failWithError:KCMakeError(KCErrorNetwork, L(@"The local video proxy could not start."))];
        return;
    }
    self.currentVariant = chosen;
    self.proxyGeneration = [KCMediaProxy shared].generation;
    if (self.variants.count < 2) self.playerView.qualityTitle = nil;   // (a clip comes in one size: nothing to choose)
    else self.playerView.qualityTitle = chosen ? [chosen title] : L(@"Auto");
    NSMutableArray *names = [NSMutableArray array];   // (renditions beyond this device marked with a cross)
    for (KCVariant *v in self.variants) [names addObject:[v.name stringByAppendingString:[KCPlayback deviceCanPlay:v] ? @"" : @"✗"]];
    KCLog(@"Renditions: %@; quality %@ -> %@", [names componentsJoinedByString:@", "], self.quality ?: @"auto", chosen ? chosen.name : @"auto (master playlist)");
    [self loadItemWithURL:url];
}

- (void)loadItemWithURL:(NSURL *)url
{
    [self detachItem];
    KCLog(@"Playing %@ (%@)", self.slug, url.lastPathComponent);
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    self.item = item;
    [item addObserver:self forKeyPath:@"status" options:0 context:KCStatusContext];
    [item addObserver:self forKeyPath:@"playbackBufferEmpty" options:0 context:KCBufferEmptyContext];
    [item addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:0 context:KCKeepUpContext];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(itemDidPlayToEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];
    [nc addObserver:self selector:@selector(itemFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:item];
    [nc addObserver:self selector:@selector(itemStalled:) name:AVPlayerItemPlaybackStalledNotification object:item];
    if (!self.player) {
        self.player = [AVPlayer playerWithPlayerItem:item];
        // (the proxy lives on this device only: a remote AirPlay screen could not reach it)
        self.player.allowsExternalPlayback = NO;
        self.playerView.player = self.player;
    } else {
        [self.player replaceCurrentItemWithPlayerItem:item];
        if (!self.inBackground) self.playerView.player = self.player;
    }
    self.lastProgressTime = [NSDate timeIntervalSinceReferenceDate];
    self.lastPosition = -1;
    [self.playerView setBuffering:YES];
    if (self.wantsToPlay) {
        [self.player play];
        self.playerView.playing = YES;
    }
}

- (void)detachItem
{
    if (!self.item) return;
    @try {
        [self.item removeObserver:self forKeyPath:@"status" context:KCStatusContext];
        [self.item removeObserver:self forKeyPath:@"playbackBufferEmpty" context:KCBufferEmptyContext];
        [self.item removeObserver:self forKeyPath:@"playbackLikelyToKeepUp" context:KCKeepUpContext];
    } @catch (NSException *e) {}
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
    [nc removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.item];
    [nc removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:self.item];
    self.item = nil;
}

- (void)teardownPlayback
{
    [self.loadTask cancel];
    self.loadTask = nil;
    [self.infoTask cancel];
    self.infoTask = nil;
    [self.replayTask cancel];
    self.replayTask = nil;
    [self.historyTask cancel];
    self.historyTask = nil;
    [self.tickTimer invalidate];
    self.tickTimer = nil;
    [self rememberPosition];
    [self.player pause];
    [self detachItem];
    self.playerView.player = nil;
    self.player = nil;
    [self.chat disconnect];
    self.chat.delegate = nil;
    self.chat = nil;
    Class center = NSClassFromString(@"MPNowPlayingInfoCenter");
    if (center) [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context != KCStatusContext && context != KCBufferEmptyContext && context != KCKeepUpContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    if (![NSThread isMainThread]) {
        // (AVFoundation reports from its own threads now and then)
        dispatch_async(dispatch_get_main_queue(), ^{ [self observeValueForKeyPath:keyPath ofObject:object change:change context:context]; });
        return;
    }
    if (object != self.item) return;
    if (context == KCStatusContext) {
        if (self.item.status == AVPlayerItemStatusFailed) {
            NSError *error = self.item.error;
            KCLog(@"Item failed: %@", error);
            [self handlePlaybackFailure:error];
        } else if (self.item.status == AVPlayerItemStatusReadyToPlay) {
            self.itemReady = YES;
            self.automaticReloads = 0;
            [self.playerView setBuffering:NO];
            if (self.pendingSeek >= 0) {
                double seek = self.pendingSeek;
                self.pendingSeek = -1;
                [self.player seekToTime:CMTimeMakeWithSeconds(seek, 600)];
            }
            if (self.wantsToPlay) [self.player play];
            [self updateNowPlaying];
        }
    } else if (context == KCBufferEmptyContext) {
        if (self.item.playbackBufferEmpty && self.wantsToPlay) [self.playerView setBuffering:YES];
    } else if (context == KCKeepUpContext) {
        if (self.item.playbackLikelyToKeepUp) {
            [self.playerView setBuffering:NO];
            if (self.wantsToPlay && self.player.rate == 0 && !self.ended) [self.player play];
        }
    }
}

- (void)itemDidPlayToEnd:(NSNotification *)note
{
    if (self.mode == KCPlayerModeLive) {
        // the playlist ended: the stream is over (or the proxy's playlist failed and the player gave up)
        [self streamEnded];
        return;
    }
    self.ended = YES;
    self.wantsToPlay = NO;
    self.playerView.playing = NO;
    if (self.mode == KCPlayerModeVideo) [KCSettings setResumePosition:0 forVideo:self.video.videoId];
    self.playerView.controlsLocked = YES;
    [self.playerView showMessage:nil retryTitle:nil];
    [self updateIdleTimer];
}

- (void)itemFailed:(NSNotification *)note
{
    NSError *error = note.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
    KCLog(@"Failed to play to end: %@", error);
    [self handlePlaybackFailure:error];
}

- (void)itemStalled:(NSNotification *)note
{
    KCLog(@"Playback stalled");
    if (self.wantsToPlay) [self.playerView setBuffering:YES];
}

- (void)streamEnded
{
    self.ended = YES;
    self.wantsToPlay = NO;
    self.playerView.playing = NO;
    [self.playerView setBuffering:NO];
    [self.playerView showMessage:L(@"The stream has ended.") retryTitle:L(@"Try Again")];
    __weak KCPlayerViewController *weakSelf = self;
    self.playerView.retryHandler = ^{ [weakSelf retryTapped]; };
    [self updateIdleTimer];
}

- (void)handlePlaybackFailure:(NSError *)error
{
    if (self.ended) return;
    if (self.mode == KCPlayerModeLive && self.automaticReloads < KCMaxAutomaticReloads) {
        // a hiccup of the stream (a new playlist, a dropped segment): a fresh start usually helps
        self.automaticReloads++;
        KCLog(@"Reloading the stream (%ld)", (long)self.automaticReloads);
        [self.playerView setBuffering:YES];
        __weak KCPlayerViewController *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            KCPlayerViewController *s = weakSelf;
            if (s && !s.ended && s.wantsToPlay) [s startPlayback];
        });
        return;
    }
    NSString *message = error.localizedDescription;
    if (self.mode == KCPlayerModeLive) message = L(@"The stream could not be played. It may have ended, or the connection is too slow.");
    else if (!message.length) message = L(@"The video could not be played.");
    [self failWithError:KCMakeError(KCErrorNetwork, message)];
}

- (void)failWithError:(NSError *)error
{
    [self.playerView setBuffering:NO];
    self.playerView.playing = NO;
    NSString *message = error.localizedDescription ?: L(@"Playback failed.");
    if (error.code == KCErrorOffline) message = L(@"The channel is not live right now.");
    [self.playerView showMessage:message retryTitle:L(@"Try Again")];
    __weak KCPlayerViewController *weakSelf = self;
    self.playerView.retryHandler = ^{ [weakSelf retryTapped]; };
    [self updateIdleTimer];
}

- (void)retryTapped
{
    self.automaticReloads = 0;
    self.wantsToPlay = YES;
    self.ended = NO;
    [self startPlayback];
    [self updateIdleTimer];
}

- (void)rememberPosition
{
    if (self.mode != KCPlayerModeVideo || !self.item || !self.itemReady) return;
    double position = CMTimeGetSeconds(self.player.currentTime);
    if (position > 0 && !isnan(position)) [KCSettings setResumePosition:position forVideo:self.video.videoId];
}

#pragma mark - Tick

- (void)tick
{
    if (!self.item) return;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    double position = CMTimeGetSeconds(self.player.currentTime);
    if (isnan(position)) position = 0;
    if (self.mode != KCPlayerModeLive) {
        double duration = CMTimeGetSeconds(self.item.duration);
        if (isnan(duration) || duration <= 0) duration = self.mode == KCPlayerModeVideo ? self.video.length : self.clip.duration;
        if (duration > 0) [self.playerView setProgress:position / duration duration:duration position:position];
        if (self.itemReady) [self feedReplayForPosition:position];
    }
    // progress watch: a playing stream whose position does not move for a long time is started again
    if (fabs(position - self.lastPosition) > 0.01) {
        self.lastPosition = position;
        self.lastProgressTime = now;
    } else if (self.wantsToPlay && self.itemReady && !self.ended && now - self.lastProgressTime > KCStallReloadAfter) {
        KCLog(@"No progress for %.0f s, reloading", now - self.lastProgressTime);
        self.lastProgressTime = now;
        if (self.mode == KCPlayerModeLive) [self startPlayback];
        else { [self.player pause]; [self.player play]; }
    }
    if (self.mode == KCPlayerModeLive) {
        if (now - self.lastInfoRefresh > KCInfoRefreshInterval) [self refreshInfo];
        [self updateStatusText];
    }
    if (self.mode == KCPlayerModeVideo && ((NSInteger)now % 15 == 0)) [self rememberPosition];
}

#pragma mark - Player view delegate

- (void)playerViewDidTapPlayPause:(KCPlayerView *)view
{
    if (self.ended) {
        if (self.mode == KCPlayerModeLive) { [self retryTapped]; return; }
        // a finished video: from the start
        self.ended = NO;
        self.wantsToPlay = YES;
        [self.player seekToTime:kCMTimeZero];
        [self.player play];
        self.playerView.playing = YES;
        self.playerView.controlsLocked = NO;
        [self resetReplayToPosition:0];
        [self updateIdleTimer];
        return;
    }
    if (self.wantsToPlay) {
        self.wantsToPlay = NO;
        [self.player pause];
        self.pausedAt = [NSDate timeIntervalSinceReferenceDate];
        self.playerView.playing = NO;
        self.playerView.controlsLocked = YES;
        [self rememberPosition];
    } else {
        self.wantsToPlay = YES;
        self.playerView.playing = YES;
        self.playerView.controlsLocked = NO;
        if (self.mode == KCPlayerModeLive && [NSDate timeIntervalSinceReferenceDate] - self.pausedAt > KCLivePauseReloadAfter) {
            [self startPlayback];   // (back to the live edge: the old playlist window is gone)
        } else {
            [self.player play];
        }
    }
    [self updateIdleTimer];
}

- (void)playerViewDidTapClose:(KCPlayerView *)view
{
    [self teardownPlayback];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)playerViewDidTapQuality:(KCPlayerView *)view fromView:(UIView *)anchor
{
    if (self.variants.count < 2) return;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:L(@"Quality") delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    sheet.tag = 1;
    [sheet addButtonWithTitle:L(@"Auto")];
    for (KCVariant *v in self.variants) {
        NSString *title = [v title];
        if (![KCPlayback deviceCanPlay:v]) title = [title stringByAppendingString:L(@" (too much for this device)")];
        [sheet addButtonWithTitle:title];
    }
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    if (KCIsPad()) [sheet showFromRect:anchor.bounds inView:anchor animated:YES];
    else [sheet showInView:self.view];
    self.playerView.controlsLocked = YES;
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    self.playerView.controlsLocked = !self.wantsToPlay;
    if (actionSheet.tag != 1 || buttonIndex < 0 || buttonIndex == actionSheet.cancelButtonIndex) return;
    if (buttonIndex == 0) {
        self.quality = KCQualityAuto;
    } else if ((NSUInteger)(buttonIndex - 1) < self.variants.count) {
        KCVariant *v = self.variants[(NSUInteger)(buttonIndex - 1)];
        self.quality = [v qualityKey];
    } else {
        return;
    }
    [KCSettings setPreferredQuality:self.quality];
    [KCSettings save];
    double position = self.item ? CMTimeGetSeconds(self.player.currentTime) : 0;
    if (self.mode != KCPlayerModeLive && !isnan(position) && position > 0) self.pendingSeek = position;
    self.ended = NO;
    [self playVariants];
}

- (void)playerViewDidTapChat:(KCPlayerView *)view
{
    self.chatVisible = !self.chatVisible;
    [KCSettings setShowChat:self.chatVisible];
    self.playerView.chatVisible = self.chatVisible;
    [self.view setNeedsLayout];
    [UIView animateWithDuration:0.25 animations:^{ [self.view layoutIfNeeded]; }];
    if (self.chatVisible && self.mode == KCPlayerModeVideo) {
        // (the replay waited while hidden: it picks up at the picture)
        double position = CMTimeGetSeconds(self.player.currentTime);
        [self resetReplayToPosition:isnan(position) ? 0 : position];
    }
}

- (void)playerViewDidTapFullscreen:(KCPlayerView *)view
{
    self.fullscreen = !self.fullscreen;
    self.playerView.fullscreen = self.fullscreen;
    [self updateStatusBar];
    [UIView animateWithDuration:0.25 animations:^{ [self.view layoutIfNeeded]; }];
}

- (void)playerViewDidTapChannel:(KCPlayerView *)view
{
    if (!self.slug.length) return;
    [KCNavigator openChannelSlug:self.slug from:self];
}

- (void)playerView:(KCPlayerView *)view didSeekToFraction:(double)fraction
{
    double duration = CMTimeGetSeconds(self.item.duration);
    if (isnan(duration) || duration <= 0) duration = self.mode == KCPlayerModeVideo ? self.video.length : self.clip.duration;
    if (duration <= 0) return;
    [self seekTo:fraction * duration];
}

- (void)playerView:(KCPlayerView *)view didSkipSeconds:(double)seconds
{
    double position = CMTimeGetSeconds(self.player.currentTime);
    if (isnan(position)) position = 0;
    [self seekTo:MAX(0, position + seconds)];
}

- (void)seekTo:(double)seconds
{
    if (!self.item) return;
    self.ended = NO;
    [self.playerView setBuffering:YES];
    [self.player seekToTime:CMTimeMakeWithSeconds(seconds, 600) toleranceBefore:CMTimeMakeWithSeconds(2, 600) toleranceAfter:CMTimeMakeWithSeconds(2, 600)];
    if (self.wantsToPlay) [self.player play];
    [self resetReplayToPosition:seconds];
}

- (void)playerViewDidTapGoLive:(KCPlayerView *)view
{
    if (self.mode != KCPlayerModeLive) return;
    self.wantsToPlay = YES;
    self.playerView.playing = YES;
    self.playerView.controlsLocked = NO;
    [self startPlayback];
}

#pragma mark - Background

- (void)didEnterBackground
{
    self.inBackground = YES;
    KCLog(@"Background: %@", self.wantsToPlay ? ([KCSettings backgroundAudio] ? @"the sound goes on" : @"paused") : @"not playing");
    if (self.wantsToPlay && [KCSettings backgroundAudio] && !self.ended) {
        // without a picture to draw the sound goes on; with the layer attached iOS pauses the player
        self.playerView.player = nil;
        __weak KCPlayerViewController *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            KCPlayerViewController *s = weakSelf;
            if (s && s.inBackground && s.wantsToPlay) [s.player play];
        });
    } else if (self.wantsToPlay) {
        [self.player pause];
        self.pausedAt = [NSDate timeIntervalSinceReferenceDate];
    }
    [self rememberPosition];
}

- (void)willEnterForeground
{
    self.inBackground = NO;
    self.playerView.player = self.player;
    KCMediaProxy *proxy = [KCMediaProxy shared];
    [proxy ensureRunning];
    KCLog(@"Foreground: proxy generation %ld (was %ld)", (long)proxy.generation, (long)self.proxyGeneration);
    if (proxy.generation != self.proxyGeneration && !self.ended) {
        // the proxy was restarted while we were away: the old addresses are void
        if (self.wantsToPlay) [self startPlayback];
        return;
    }
    if (self.wantsToPlay && !self.ended) {
        if (self.mode == KCPlayerModeLive && ![KCSettings backgroundAudio] && [NSDate timeIntervalSinceReferenceDate] - self.pausedAt > KCLivePauseReloadAfter) [self startPlayback];
        else [self.player play];
    }
    [self updateStatusBar];
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)event
{
    if (event.type != UIEventTypeRemoteControl) return;
    switch (event.subtype) {
        case UIEventSubtypeRemoteControlTogglePlayPause:
            [self playerViewDidTapPlayPause:self.playerView];
            break;
        case UIEventSubtypeRemoteControlPlay:
            if (!self.wantsToPlay) [self playerViewDidTapPlayPause:self.playerView];
            break;
        case UIEventSubtypeRemoteControlPause:
        case UIEventSubtypeRemoteControlStop:
            if (self.wantsToPlay) [self playerViewDidTapPlayPause:self.playerView];
            break;
        default:
            break;
    }
}

#pragma mark - Live chat

- (void)startChatIfNeeded
{
    if (self.mode != KCPlayerModeLive || self.chat || !self.channel.chatroomId.length) return;
    // the last messages first, so the chat does not start empty; live ones arriving meanwhile wait behind them
    self.heldMessages = [NSMutableArray array];
    __weak KCPlayerViewController *weakSelf = self;
    self.historyTask = [KCAPI recentMessagesForChannelId:self.channel.userId completion:^(NSArray *messages, NSError *error) {
        KCPlayerViewController *s = weakSelf;
        if (!s) return;
        s.historyTask = nil;
        [s releaseHeldMessagesAfter:messages];
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(KCHistoryWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        KCPlayerViewController *s = weakSelf;
        if (!s || !s.heldMessages) return;
        [s.historyTask cancel];
        s.historyTask = nil;
        [s releaseHeldMessagesAfter:nil];
    });
    self.chat = [[KCChat alloc] initWithChatroomId:self.channel.chatroomId channel:self.slug];
    self.chat.delegate = self;
    [self.chat connect];
}

- (void)releaseHeldMessagesAfter:(NSArray *)history
{
    NSArray *held = self.heldMessages;
    if (!held) return;
    self.heldMessages = nil;
    NSMutableSet *liveIds = [NSMutableSet set];
    for (KCChatMessage *m in held) if (m.messageId) [liveIds addObject:m.messageId];
    NSMutableArray *lines = [NSMutableArray array];
    for (KCChatMessage *m in history) if (!m.messageId || ![liveIds containsObject:m.messageId]) [lines addObject:m];
    [lines addObjectsFromArray:held];
    [self.chatView appendMessages:lines];
}

- (void)showLive:(NSArray *)messages
{
    if (self.heldMessages) [self.heldMessages addObjectsFromArray:messages];
    else [self.chatView appendMessages:messages];
}

- (void)chat:(KCChat *)chat didReceiveMessages:(NSArray *)messages
{
    [self showLive:messages];
}

- (void)chat:(KCChat *)chat didChangeState:(KCChatState)state
{
    if (state != KCChatStateConnected) return;
    [self showLive:@[ [KCChatMessage noticeWithText:[NSString stringWithFormat:L(@"Connected to the chat of %@."), [self channelName]]] ]];
}

- (void)chat:(KCChat *)chat didUpdateRoomState:(NSDictionary *)state
{
    NSMutableArray *modes = [NSMutableArray array];
    if ([state[@"emoteOnly"] boolValue]) [modes addObject:L(@"emotes only")];
    if ([state[@"subscribersOnly"] boolValue]) [modes addObject:L(@"subscribers only")];
    NSInteger followers = state[@"followersOnly"] ? [state[@"followersOnly"] integerValue] : -1;
    if (followers >= 0) [modes addObject:followers > 0 ? [NSString stringWithFormat:L(@"followers only (%ld min)"), (long)followers] : L(@"followers only")];
    NSInteger slow = [state[@"slow"] integerValue];
    if (slow > 0) [modes addObject:[NSString stringWithFormat:L(@"slow mode %ld s"), (long)slow]];
    NSString *text = modes.count ? [NSString stringWithFormat:L(@"Chat mode: %@."), [modes componentsJoinedByString:@", "]] : nil;
    // (announced when it changes, not with every update of the room)
    if (text && ![text isEqualToString:self.roomModes]) [self showLive:@[ [KCChatMessage noticeWithText:text] ]];
    self.roomModes = text;
}

- (void)chat:(KCChat *)chat didClearMessagesOfUser:(NSString *)slug seconds:(NSInteger)seconds
{
    [self.chatView clearMessagesOfUser:slug seconds:seconds];
}

- (void)chat:(KCChat *)chat didDeleteMessageWithId:(NSString *)messageId
{
    [self.chatView deleteMessageWithId:messageId];
}

- (void)chatView:(KCChatView *)chatView didTapName:(NSString *)slug displayName:(NSString *)displayName
{
    if (slug.length) [KCNavigator openChannelSlug:slug from:self];
}

- (void)chatView:(KCChatView *)chatView didTapLink:(NSString *)url
{
    NSURL *u = [NSURL URLWithString:url];
    if (!u) return;
    // a chooser: copy the link, or open it in Safari or Surfari (the user's own iOS 6 browser)
    [KCExternalOpen presentShareSheetForURL:u from:self anchor:nil];
}

#pragma mark - Chat replay (recordings)

// Kick keeps the chat of a broadcast: asked for a moment, it answers with the messages of the next few seconds.
// The replay walks along in such windows a little ahead of the picture and lets each line out at its moment.
- (void)startReplay
{
    if (!self.video.publishedAt || !self.channelId.length) {
        [self.chatView appendNotice:L(@"There is no chat replay for this video.")];
        return;
    }
    [self.chatView appendNotice:L(@"Chat replay: the messages appear as they did during the broadcast.")];
}

- (void)resetReplayToPosition:(double)seconds
{
    if (self.mode != KCPlayerModeVideo) return;
    [self.replayTask cancel];
    self.replayTask = nil;
    [self.replayQueue removeAllObjects];
    [self.replaySeen removeAllObjects];
    [self.chatView removeAllMessages];
    self.replayFetchedUpTo = MAX(0, seconds - 10);   // (a little of what was written just before)
    self.replayRetryAt = 0;
}

- (void)feedReplayForPosition:(double)seconds
{
    if (self.mode != KCPlayerModeVideo || !self.chatVisible || !self.video.publishedAt || !self.channelId.length) return;
    // the lines that are due (those left far behind by a jump of the picture are dropped)
    NSMutableArray *due = [NSMutableArray array];
    while (self.replayQueue.count) {
        KCChatMessage *m = self.replayQueue[0];
        if (m.replayOffset > seconds) break;
        if (m.replayOffset > seconds - 60) [due addObject:m];
        [self.replayQueue removeObjectAtIndex:0];
    }
    if (due.count) [self.chatView appendMessages:due];
    // the next window, unless the replay is far enough ahead
    if (self.replayTask || [NSDate timeIntervalSinceReferenceDate] < self.replayRetryAt) return;
    if (self.replayFetchedUpTo < 0 || self.replayFetchedUpTo < seconds - 2 * KCReplayLead) {
        // the first window, or the picture ran ahead (a resumed video): from a little before the position
        self.replayFetchedUpTo = MAX(0, seconds - 10);
    }
    if (self.replayFetchedUpTo > seconds + KCReplayLead) return;
    if (self.video.length > 0 && self.replayFetchedUpTo > self.video.length) return;
    double from = self.replayFetchedUpTo;
    NSDate *start = self.video.publishedAt;
    __weak KCPlayerViewController *weakSelf = self;
    self.replayTask = [KCAPI chatReplayForChannelId:self.channelId at:[start dateByAddingTimeInterval:from] completion:^(NSArray *messages, NSError *error) {
        KCPlayerViewController *s = weakSelf;
        if (!s) return;
        s.replayTask = nil;
        if (error) {
            KCLog(@"Chat replay: %@", error.localizedDescription);
            s.replayRetryAt = [NSDate timeIntervalSinceReferenceDate] + 5;
            return;
        }
        NSMutableSet *ids = [NSMutableSet set];
        for (KCChatMessage *m in messages) {
            if (m.messageId && [s.replaySeen containsObject:m.messageId]) continue;
            if (m.messageId) [ids addObject:m.messageId];
            m.replayOffset = MAX(0, [m.timestamp timeIntervalSinceDate:start]);
            [s.replayQueue addObject:m];
        }
        s.replaySeen = ids;
        s.replayFetchedUpTo = from + KCReplayWindow;
    }];
}

#pragma mark - Replacement

- (void)replaceWithPlayer:(KCPlayerViewController *)player
{
    UIViewController *presenter = self.presentingViewController ?: [UIApplication sharedApplication].keyWindow.rootViewController;
    [self teardownPlayback];
    // (dismissed from below: that closes this player together with whatever it showed on top, a channel page)
    [presenter dismissViewControllerAnimated:NO completion:^{
        player.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        [presenter presentViewController:player animated:YES completion:nil];
    }];
}

@end
