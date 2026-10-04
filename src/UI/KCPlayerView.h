#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@class KCPlayerView;

@protocol KCPlayerViewDelegate <NSObject>
- (void)playerViewDidTapPlayPause:(KCPlayerView *)view;
- (void)playerViewDidTapClose:(KCPlayerView *)view;
- (void)playerViewDidTapQuality:(KCPlayerView *)view fromView:(UIView *)anchor;
- (void)playerViewDidTapChat:(KCPlayerView *)view;
- (void)playerViewDidTapFullscreen:(KCPlayerView *)view;
- (void)playerViewDidTapChannel:(KCPlayerView *)view;
- (void)playerView:(KCPlayerView *)view didSeekToFraction:(double)fraction;    // videos and clips
- (void)playerView:(KCPlayerView *)view didSkipSeconds:(double)seconds;        // -10 / +10
- (void)playerViewDidTapGoLive:(KCPlayerView *)view;                            // live: back to the live edge
@end

// The video (AVPlayerLayer) with the controls drawn over it: a top bar with the title and the quality, a bottom bar
// with play/pause, LIVE or the time slider, chat and full screen buttons, a spinner and messages in the middle.
// The controls hide by themselves after a few seconds; a tap shows them again.
@interface KCPlayerView : UIView

@property (nonatomic, weak) id<KCPlayerViewDelegate> delegate;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, readonly) AVPlayerLayer *playerLayer;

@property (nonatomic) BOOL isLive;                   // LIVE badge instead of the slider
@property (nonatomic) BOOL playing;                  // the play/pause button's state
@property (nonatomic) BOOL fullscreen;               // the button's state
@property (nonatomic) BOOL chatVisible;
@property (nonatomic) BOOL chatButtonHidden;         // (no chat for clips)
@property (nonatomic) BOOL closeIsBack;              // a chevron instead of an X (a stack behind this screen)
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;      // channel · category
@property (nonatomic, copy) NSString *qualityTitle;
@property (nonatomic, copy) NSString *statusText;    // viewers · uptime, or the position in a video

- (void)setBuffering:(BOOL)buffering;                // spinner in the middle
- (void)showMessage:(NSString *)text retryTitle:(NSString *)retry;   // an error with a button; nil hides it
@property (nonatomic, copy) dispatch_block_t retryHandler;
- (void)setProgress:(double)fraction duration:(NSTimeInterval)duration position:(NSTimeInterval)position;   // videos
- (void)showControls:(BOOL)show animated:(BOOL)animated;
- (void)showControlsBriefly;
@property (nonatomic, readonly) BOOL controlsVisible;
@property (nonatomic) BOOL controlsLocked;           // stay visible (while paused, while an error shows)
@property (nonatomic) CGFloat topInset;              // room for the status bar

@end
