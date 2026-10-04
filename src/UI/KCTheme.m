#import "KCTheme.h"
#import "KCSettings.h"
#import "KCUtils.h"
#import "KCCommon.h"

static UIColor *RGB(NSInteger r, NSInteger g, NSInteger b)
{
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1.0];
}

static void KCDrawVerticalGradient(CGContextRef ctx, CGRect rect, UIColor *top, UIColor *bottom)
{
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[ (id)top.CGColor, (id)bottom.CGColor ];
    CGFloat locations[2] = { 0.0, 1.0 };
    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, locations);
    CGContextDrawLinearGradient(ctx, gradient, CGPointMake(rect.origin.x, CGRectGetMinY(rect)), CGPointMake(rect.origin.x, CGRectGetMaxY(rect)), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
}

// A rounded, vertically shaded rectangle with an optional glossy top half, as a stretchable image.
static UIImage *KCRoundedGradientImage(UIColor *top, UIColor *bottom, UIColor *stroke, CGFloat radius, BOOL gloss)
{
    CGFloat side = radius * 2 + 12;
    CGRect rect = CGRectMake(0, 0, side, side);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect inner = CGRectInset(rect, 0.5, 0.5);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:inner cornerRadius:radius];
    CGContextSaveGState(ctx);
    CGContextAddPath(ctx, path.CGPath);
    CGContextClip(ctx);
    KCDrawVerticalGradient(ctx, rect, top, bottom);
    if (gloss) {
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.22].CGColor);
        CGContextFillRect(ctx, CGRectMake(0, 0, side, floor(side / 2)));
    }
    CGContextRestoreGState(ctx);
    if (stroke) {
        [stroke setStroke];
        path.lineWidth = 1.0;
        [path stroke];
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CGFloat cap = radius + 5;
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(cap, cap, cap, cap) resizingMode:UIImageResizingModeStretch];
}

// A bar background: top highlight hairline, gradient body, bottom line.
static UIImage *KCBarImage(UIColor *top, UIColor *bottom, UIColor *line, CGFloat height)
{
    CGSize size = CGSizeMake(4, height);
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    KCDrawVerticalGradient(ctx, CGRectMake(0, 0, size.width, height), top, bottom);
    [[UIColor colorWithWhite:1.0 alpha:0.35] setFill];
    UIRectFill(CGRectMake(0, 0, size.width, 1));
    [line setFill];
    UIRectFill(CGRectMake(0, height - 1, size.width, 1));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(2, 1, 2, 1) resizingMode:UIImageResizingModeStretch];
}

// Draws with a block into an image of the given size (transparent background)
static UIImage *KCDrawImage(CGSize size, void (^draw)(CGContextRef ctx))
{
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    draw(UIGraphicsGetCurrentContext());
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@interface KCTheme ()
@property (nonatomic) BOOL dark;
@property (nonatomic, strong) NSMutableDictionary *imageCache;
@end

@implementation KCTheme

+ (instancetype)shared
{
    static KCTheme *theme;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ theme = [[KCTheme alloc] init]; });
    return theme;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _dark = [KCSettings darkTheme];
        _imageCache = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)isDark { return self.dark; }

- (void)setDark:(BOOL)dark
{
    _dark = dark;
    [KCSettings setDarkTheme:dark];
    [KCSettings save];
    [self.imageCache removeAllObjects];
    [[UIApplication sharedApplication] setStatusBarStyle:[self statusBarStyle] animated:YES];
    [[NSNotificationCenter defaultCenter] postNotificationName:KCThemeDidChangeNotification object:self];
}

- (void)invalidateArtwork
{
    [self.imageCache removeAllObjects];
    [[NSNotificationCenter defaultCenter] postNotificationName:KCThemeDidChangeNotification object:self];
}

#pragma mark - Colors

// (dark is the house look: near black surfaces and the bright green; the light look keeps a deeper green for text)
- (UIColor *)backgroundColor { return self.dark ? RGB(11, 13, 14) : RGB(228, 232, 228); }
- (UIColor *)cardColor { return self.dark ? RGB(25, 27, 31) : [UIColor whiteColor]; }
- (UIColor *)primaryTextColor { return self.dark ? RGB(239, 241, 239) : RGB(20, 24, 20); }
- (UIColor *)secondaryTextColor { return self.dark ? RGB(146, 152, 148) : RGB(104, 112, 106); }
- (UIColor *)separatorColor { return self.dark ? RGB(44, 48, 50) : RGB(198, 204, 198); }
- (UIColor *)accentColor { return self.dark ? RGB(83, 252, 24) : RGB(38, 150, 12); }
- (UIColor *)liveColor { return RGB(83, 252, 24); }
- (UIColor *)linkColor { return self.dark ? RGB(130, 230, 100) : RGB(28, 120, 10); }
- (UIColor *)chatBackgroundColor { return self.dark ? RGB(17, 19, 21) : RGB(250, 251, 250); }
- (UIColor *)chatTextColor { return self.dark ? RGB(235, 238, 235) : RGB(24, 28, 24); }
- (UIColor *)chatSystemTextColor { return self.dark ? RGB(146, 152, 148) : RGB(104, 112, 106); }
- (UIColor *)chatHighlightColor { return self.dark ? RGB(24, 44, 18) : RGB(230, 250, 220); }
- (UIColor *)chatDeletedTextColor { return self.dark ? RGB(112, 118, 114) : RGB(150, 156, 150); }
- (UIColor *)chatSeparatorColor { return self.dark ? RGB(32, 35, 37) : RGB(232, 236, 232); }
- (UIColor *)switchTintColor { return self.dark ? RGB(70, 215, 20) : RGB(52, 175, 16); }
- (UIColor *)playerBackgroundColor { return [UIColor blackColor]; }

#pragma mark - Artwork

- (UIImage *)cachedImage:(NSString *)key builder:(UIImage *(^)(void))builder
{
    UIImage *image = self.imageCache[key];
    if (!image) {
        image = builder();
        if (image) self.imageCache[key] = image;
    }
    return image;
}

- (UIImage *)cardBackgroundImage
{
    return [self cachedImage:@"card" builder:^UIImage *{
        if (self.dark) return KCRoundedGradientImage(RGB(44, 44, 49), RGB(32, 32, 36), RGB(60, 60, 66), 6, NO);
        return KCRoundedGradientImage(RGB(255, 255, 255), RGB(246, 246, 249), RGB(188, 190, 198), 6, NO);
    }];
}

- (UIImage *)cardBackgroundImageHighlighted
{
    return [self cachedImage:@"card-hi" builder:^UIImage *{
        if (self.dark) return KCRoundedGradientImage(RGB(60, 60, 66), RGB(48, 48, 54), RGB(75, 75, 82), 6, NO);
        return KCRoundedGradientImage(RGB(222, 226, 236), RGB(208, 213, 226), RGB(170, 175, 190), 6, NO);
    }];
}

- (UIImage *)pillImageWithColor:(UIColor *)color
{
    CGFloat r = 0, g = 0, b = 0, a = 1;
    [color getRed:&r green:&g blue:&b alpha:&a];
    NSString *key = [NSString stringWithFormat:@"pill-%.2f-%.2f-%.2f", r, g, b];
    return [self cachedImage:key builder:^UIImage *{
        UIColor *top = [UIColor colorWithRed:MIN(1, r + 0.15) green:MIN(1, g + 0.15) blue:MIN(1, b + 0.15) alpha:1];
        UIColor *bottom = [UIColor colorWithRed:r * 0.8 green:g * 0.8 blue:b * 0.8 alpha:1];
        UIColor *stroke = [UIColor colorWithRed:r * 0.6 green:g * 0.6 blue:b * 0.6 alpha:1];
        return KCRoundedGradientImage(top, bottom, stroke, 8, YES);
    }];
}

- (UIImage *)darkPillImage
{
    return [self cachedImage:@"pill-dark" builder:^UIImage *{
        return KCRoundedGradientImage([UIColor colorWithWhite:0 alpha:0.62], [UIColor colorWithWhite:0 alpha:0.72], nil, 7, NO);
    }];
}

- (UIImage *)buttonImageHighlighted:(BOOL)highlighted
{
    NSString *key = highlighted ? @"button-hi" : @"button";
    return [self cachedImage:key builder:^UIImage *{
        if (self.dark) {
            if (highlighted) return KCRoundedGradientImage(RGB(70, 70, 76), RGB(50, 50, 56), RGB(20, 20, 24), 6, YES);
            return KCRoundedGradientImage(RGB(100, 100, 106), RGB(66, 66, 72), RGB(20, 20, 24), 6, YES);
        }
        if (highlighted) return KCRoundedGradientImage(RGB(200, 203, 212), RGB(170, 174, 186), RGB(120, 124, 136), 6, YES);
        return KCRoundedGradientImage(RGB(250, 250, 252), RGB(214, 216, 225), RGB(140, 144, 156), 6, YES);
    }];
}

- (UIImage *)accentButtonImageHighlighted:(BOOL)highlighted disabled:(BOOL)disabled
{
    NSString *key = [NSString stringWithFormat:@"accent-%d-%d", (int)highlighted, (int)disabled];
    return [self cachedImage:key builder:^UIImage *{
        // (green glass; the lettering on it is black)
        if (disabled) return KCRoundedGradientImage(RGB(170, 180, 170), RGB(140, 150, 140), RGB(110, 120, 110), 7, YES);
        if (highlighted) return KCRoundedGradientImage(RGB(64, 190, 18), RGB(38, 132, 8), RGB(26, 96, 4), 7, YES);
        return KCRoundedGradientImage(RGB(140, 255, 96), RGB(72, 214, 20), RGB(42, 150, 8), 7, YES);
    }];
}

- (UIImage *)thumbnailPlaceholder
{
    return [self cachedImage:@"thumb" builder:^UIImage *{
        return KCDrawImage(CGSizeMake(64, 36), ^(CGContextRef ctx) {
            KCDrawVerticalGradient(ctx, CGRectMake(0, 0, 64, 36), RGB(70, 70, 78), RGB(40, 40, 46));
            UIBezierPath *play = [UIBezierPath bezierPath];
            [play moveToPoint:CGPointMake(27, 11)];
            [play addLineToPoint:CGPointMake(40, 18)];
            [play addLineToPoint:CGPointMake(27, 25)];
            [play closePath];
            [[UIColor colorWithWhite:1 alpha:0.25] setFill];
            [play fill];
        });
    }];
}

- (UIImage *)categoryPlaceholder
{
    return [self cachedImage:@"category" builder:^UIImage *{
        return KCDrawImage(CGSizeMake(30, 40), ^(CGContextRef ctx) {
            KCDrawVerticalGradient(ctx, CGRectMake(0, 0, 30, 40), RGB(44, 70, 38), RGB(20, 32, 18));
        });
    }];
}

- (UIImage *)avatarPlaceholderWithSize:(CGFloat)size
{
    NSString *key = [NSString stringWithFormat:@"avatar-%.0f", size];
    return [self cachedImage:key builder:^UIImage *{
        return KCDrawImage(CGSizeMake(size, size), ^(CGContextRef ctx) {
            [(self.dark ? RGB(70, 70, 78) : RGB(190, 192, 200)) setFill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size, size)] fill];
            [(self.dark ? RGB(110, 110, 120) : RGB(240, 240, 244)) setFill];
            CGFloat head = size * 0.34;
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake((size - head) / 2, size * 0.18, head, head)] fill];
            UIBezierPath *body = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(size * 0.15, size * 0.58, size * 0.7, size * 0.6)];
            CGContextSaveGState(ctx);
            CGContextAddEllipseInRect(ctx, CGRectMake(0, 0, size, size));
            CGContextClip(ctx);
            [body fill];
            CGContextRestoreGState(ctx);
        });
    }];
}

- (UIImage *)sectionHeaderBackgroundImage
{
    return [self cachedImage:@"section" builder:^UIImage *{
        if (self.dark) return KCBarImage(RGB(58, 58, 64), RGB(40, 40, 45), RGB(20, 20, 24), 22);
        return KCBarImage(RGB(176, 188, 206), RGB(144, 159, 184), RGB(110, 125, 150), 22);
    }];
}

- (UIImage *)controlsGradientImageTop:(BOOL)top
{
    NSString *key = top ? @"ctl-top" : @"ctl-bottom";
    return [self cachedImage:key builder:^UIImage *{
        UIImage *image = KCDrawImage(CGSizeMake(4, 64), ^(CGContextRef ctx) {
            UIColor *a = [UIColor colorWithWhite:0 alpha:top ? 0.75 : 0.0], *b = [UIColor colorWithWhite:0 alpha:top ? 0.0 : 0.75];
            KCDrawVerticalGradient(ctx, CGRectMake(0, 0, 4, 64), a, b);
        });
        return [image resizableImageWithCapInsets:UIEdgeInsetsMake(0, 1, 0, 1) resizingMode:UIImageResizingModeStretch];
    }];
}

#pragma mark - Icons

// Tab bar icons are alpha masks: UIKit colours them itself
- (UIImage *)tabIconFavorites
{
    return [self cachedImage:@"tab-star" builder:^UIImage *{
        return [self starIconFilled:YES color:[UIColor blackColor] size:30];
    }];
}

- (UIImage *)tabIconBrowse
{
    return [self cachedImage:@"tab-browse" builder:^UIImage *{
        return KCDrawImage(CGSizeMake(30, 30), ^(CGContextRef ctx) {
            [[UIColor blackColor] setFill];
            UIBezierPath *screen = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(2, 5, 26, 18) cornerRadius:3];
            [screen fill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(9, 24, 12, 3) cornerRadius:1.5] fill];
            CGContextSetBlendMode(ctx, kCGBlendModeClear);
            UIBezierPath *play = [UIBezierPath bezierPath];
            [play moveToPoint:CGPointMake(12, 9)];
            [play addLineToPoint:CGPointMake(20, 14)];
            [play addLineToPoint:CGPointMake(12, 19)];
            [play closePath];
            [play fill];
        });
    }];
}

- (UIImage *)tabIconCategories
{
    return [self cachedImage:@"tab-categories" builder:^UIImage *{
        return KCDrawImage(CGSizeMake(30, 30), ^(CGContextRef ctx) {
            [[UIColor blackColor] setFill];
            CGFloat s = 11, gap = 3, x0 = 2.5, y0 = 2.5;
            for (int row = 0; row < 2; row++) {
                for (int col = 0; col < 2; col++) {
                    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x0 + col * (s + gap), y0 + row * (s + gap), s, s) cornerRadius:2.5] fill];
                }
            }
        });
    }];
}

- (UIImage *)tabIconSearch
{
    return [self cachedImage:@"tab-search" builder:^UIImage *{
        return KCDrawImage(CGSizeMake(30, 30), ^(CGContextRef ctx) {
            [[UIColor blackColor] setStroke];
            UIBezierPath *lens = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(4, 4, 15, 15)];
            lens.lineWidth = 3.5;
            [lens stroke];
            UIBezierPath *handle = [UIBezierPath bezierPath];
            [handle moveToPoint:CGPointMake(17, 17)];
            [handle addLineToPoint:CGPointMake(26, 26)];
            handle.lineWidth = 4.5;
            handle.lineCapStyle = kCGLineCapRound;
            [handle stroke];
        });
    }];
}

- (UIImage *)gearPathImageSize:(CGFloat)size color:(UIColor *)color
{
    return KCDrawImage(CGSizeMake(size, size), ^(CGContextRef ctx) {
        CGFloat c = size / 2;
        CGContextTranslateCTM(ctx, c, c);
        [color setFill];
        CGFloat outer = size * 0.33, toothW = size * 0.17, toothH = size * 0.14;
        for (int i = 0; i < 8; i++) {
            CGContextSaveGState(ctx);
            CGContextRotateCTM(ctx, i * M_PI / 4);
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(-toothW / 2, -outer - toothH, toothW, toothH + 3) cornerRadius:1.5] fill];
            CGContextRestoreGState(ctx);
        }
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(-outer, -outer, outer * 2, outer * 2)] fill];
        CGContextSetBlendMode(ctx, kCGBlendModeClear);
        CGFloat hole = size * 0.14;
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(-hole, -hole, hole * 2, hole * 2)] fill];
    });
}

- (UIImage *)tabIconSettings
{
    return [self cachedImage:@"tab-settings" builder:^UIImage *{
        return [self gearPathImageSize:30 color:[UIColor blackColor]];
    }];
}

- (UIImage *)playIcon
{
    return [self cachedImage:@"play" builder:^UIImage *{
        return KCDrawImage(CGSizeMake(30, 30), ^(CGContextRef ctx) {
            UIBezierPath *p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(8, 4)];
            [p addLineToPoint:CGPointMake(26, 15)];
            [p addLineToPoint:CGPointMake(8, 26)];
            [p closePath];
            [[UIColor whiteColor] setFill];
            [p fill];
        });
    }];
}

- (UIImage *)pauseIcon
{
    return [self cachedImage:@"pause" builder:^UIImage *{
        return KCDrawImage(CGSizeMake(30, 30), ^(CGContextRef ctx) {
            [[UIColor whiteColor] setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(7, 4, 6, 22) cornerRadius:1] fill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(17, 4, 6, 22) cornerRadius:1] fill];
        });
    }];
}

- (UIImage *)fullscreenIconEnter:(BOOL)enter
{
    NSString *key = enter ? @"fs-enter" : @"fs-exit";
    return [self cachedImage:key builder:^UIImage *{
        return KCDrawImage(CGSizeMake(30, 30), ^(CGContextRef ctx) {
            [[UIColor whiteColor] setStroke];
            UIBezierPath *p = [UIBezierPath bezierPath];
            p.lineWidth = 2.5;
            p.lineCapStyle = kCGLineCapRound;
            p.lineJoinStyle = kCGLineJoinRound;
            CGFloat a = 5, b = 12, c = 18, d = 25;   // outer and inner coordinates
            if (enter) {
                [p moveToPoint:CGPointMake(a, b)]; [p addLineToPoint:CGPointMake(a, a)]; [p addLineToPoint:CGPointMake(b, a)];
                [p moveToPoint:CGPointMake(c, a)]; [p addLineToPoint:CGPointMake(d, a)]; [p addLineToPoint:CGPointMake(d, b)];
                [p moveToPoint:CGPointMake(d, c)]; [p addLineToPoint:CGPointMake(d, d)]; [p addLineToPoint:CGPointMake(c, d)];
                [p moveToPoint:CGPointMake(b, d)]; [p addLineToPoint:CGPointMake(a, d)]; [p addLineToPoint:CGPointMake(a, c)];
            } else {
                [p moveToPoint:CGPointMake(b, a)]; [p addLineToPoint:CGPointMake(b, b)]; [p addLineToPoint:CGPointMake(a, b)];
                [p moveToPoint:CGPointMake(c, a)]; [p addLineToPoint:CGPointMake(c, b)]; [p addLineToPoint:CGPointMake(d, b)];
                [p moveToPoint:CGPointMake(d, c)]; [p addLineToPoint:CGPointMake(c, c)]; [p addLineToPoint:CGPointMake(c, d)];
                [p moveToPoint:CGPointMake(b, d)]; [p addLineToPoint:CGPointMake(b, c)]; [p addLineToPoint:CGPointMake(a, c)];
            }
            [p stroke];
        });
    }];
}

- (UIImage *)chatIconOn:(BOOL)on
{
    NSString *key = on ? @"chat-on" : @"chat-off";
    return [self cachedImage:key builder:^UIImage *{
        return KCDrawImage(CGSizeMake(30, 30), ^(CGContextRef ctx) {
            UIBezierPath *bubble = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(3, 4, 24, 17) cornerRadius:5];
            UIBezierPath *tail = [UIBezierPath bezierPath];
            [tail moveToPoint:CGPointMake(9, 20)];
            [tail addLineToPoint:CGPointMake(7, 27)];
            [tail addLineToPoint:CGPointMake(15, 20.5)];
            [tail closePath];
            [bubble appendPath:tail];
            if (on) {
                [[UIColor whiteColor] setFill];
                [bubble fill];
                CGContextSetBlendMode(ctx, kCGBlendModeClear);
                [[UIColor blackColor] setFill];
                [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(8, 9, 14, 2) cornerRadius:1] fill];
                [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(8, 14, 10, 2) cornerRadius:1] fill];
            } else {
                [[UIColor whiteColor] setStroke];
                bubble.lineWidth = 2;
                bubble.lineJoinStyle = kCGLineJoinRound;
                [bubble stroke];
            }
        });
    }];
}

- (UIImage *)gearIconWhite
{
    return [self cachedImage:@"gear-white" builder:^UIImage *{
        return [self gearPathImageSize:28 color:[UIColor whiteColor]];
    }];
}

- (UIImage *)closeIconWhite
{
    return [self cachedImage:@"close-white" builder:^UIImage *{
        return KCDrawImage(CGSizeMake(24, 24), ^(CGContextRef ctx) {
            UIBezierPath *p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(6, 6)]; [p addLineToPoint:CGPointMake(18, 18)];
            [p moveToPoint:CGPointMake(18, 6)]; [p addLineToPoint:CGPointMake(6, 18)];
            p.lineWidth = 3;
            p.lineCapStyle = kCGLineCapRound;
            [[UIColor whiteColor] setStroke];
            [p stroke];
        });
    }];
}

- (UIImage *)backChevronWhite
{
    return [self cachedImage:@"back-white" builder:^UIImage *{
        return KCDrawImage(CGSizeMake(24, 24), ^(CGContextRef ctx) {
            UIBezierPath *p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(16, 3)];
            [p addLineToPoint:CGPointMake(7, 12)];
            [p addLineToPoint:CGPointMake(16, 21)];
            p.lineWidth = 3.5;
            p.lineCapStyle = kCGLineCapRound;
            p.lineJoinStyle = kCGLineJoinRound;
            [[UIColor whiteColor] setStroke];
            [p stroke];
        });
    }];
}

- (UIImage *)replayIcon
{
    return [self cachedImage:@"replay" builder:^UIImage *{
        return KCDrawImage(CGSizeMake(30, 30), ^(CGContextRef ctx) {
            UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:CGPointMake(15, 15) radius:9 startAngle:-M_PI * 0.3 endAngle:M_PI * 1.5 clockwise:YES];
            arc.lineWidth = 3;
            arc.lineCapStyle = kCGLineCapRound;
            [[UIColor whiteColor] setStroke];
            [arc stroke];
            UIBezierPath *head = [UIBezierPath bezierPath];
            [head moveToPoint:CGPointMake(18, 1)];
            [head addLineToPoint:CGPointMake(24, 6)];
            [head addLineToPoint:CGPointMake(17, 9)];
            [head closePath];
            [[UIColor whiteColor] setFill];
            [head fill];
        });
    }];
}

- (UIImage *)skipIconForward:(BOOL)forward
{
    NSString *key = forward ? @"skip-fwd" : @"skip-back";
    return [self cachedImage:key builder:^UIImage *{
        return KCDrawImage(CGSizeMake(30, 30), ^(CGContextRef ctx) {
            if (!forward) {
                CGContextTranslateCTM(ctx, 30, 0);
                CGContextScaleCTM(ctx, -1, 1);
            }
            [[UIColor whiteColor] setFill];
            UIBezierPath *a = [UIBezierPath bezierPath];
            [a moveToPoint:CGPointMake(4, 6)]; [a addLineToPoint:CGPointMake(15, 15)]; [a addLineToPoint:CGPointMake(4, 24)]; [a closePath];
            [a fill];
            UIBezierPath *b = [UIBezierPath bezierPath];
            [b moveToPoint:CGPointMake(15, 6)]; [b addLineToPoint:CGPointMake(26, 15)]; [b addLineToPoint:CGPointMake(15, 24)]; [b closePath];
            [b fill];
        });
    }];
}

- (UIImage *)starIconFilled:(BOOL)filled color:(UIColor *)color size:(CGFloat)size
{
    CGFloat r = 0, g = 0, b = 0, a = 1;
    [color getRed:&r green:&g blue:&b alpha:&a];
    NSString *key = [NSString stringWithFormat:@"star-%d-%.0f-%.2f-%.2f-%.2f", (int)filled, size, r, g, b];
    return [self cachedImage:key builder:^UIImage *{
        return KCDrawImage(CGSizeMake(size, size), ^(CGContextRef ctx) {
            UIBezierPath *star = [UIBezierPath bezierPath];
            CGFloat cx = size / 2, cy = size / 2 + size * 0.03, outer = size * 0.46, inner = outer * 0.42;
            for (int i = 0; i < 10; i++) {
                CGFloat radius = (i % 2 == 0) ? outer : inner;
                CGFloat angle = -M_PI / 2 + i * M_PI / 5;
                CGPoint p = CGPointMake(cx + radius * cos(angle), cy + radius * sin(angle));
                if (i == 0) [star moveToPoint:p]; else [star addLineToPoint:p];
            }
            [star closePath];
            star.lineJoinStyle = kCGLineJoinRound;
            if (filled) {
                [color setFill];
                [star fill];
            } else {
                [color setStroke];
                star.lineWidth = MAX(1.5, size / 14);
                [star stroke];
            }
        });
    }];
}

- (UIImage *)liveDotImage
{
    return [self cachedImage:@"live-dot" builder:^UIImage *{
        return KCDrawImage(CGSizeMake(10, 10), ^(CGContextRef ctx) {
            [[self liveColor] setFill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(1, 1, 8, 8)] fill];
            [[UIColor colorWithWhite:1 alpha:0.45] setFill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(2.5, 2, 4, 3)] fill];
        });
    }];
}

- (UIImage *)checkmarkImage
{
    return [self cachedImage:@"check" builder:^UIImage *{
        return KCDrawImage(CGSizeMake(18, 18), ^(CGContextRef ctx) {
            UIBezierPath *p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(3, 9.5)];
            [p addLineToPoint:CGPointMake(7.5, 14)];
            [p addLineToPoint:CGPointMake(15.5, 4)];
            p.lineWidth = 3;
            p.lineCapStyle = kCGLineCapRound;
            p.lineJoinStyle = kCGLineJoinRound;
            [[self accentColor] setStroke];
            [p stroke];
        });
    }];
}

- (UIImage *)disclosureChevronImage
{
    return [self cachedImage:@"chevron" builder:^UIImage *{
        return KCDrawImage(CGSizeMake(12, 20), ^(CGContextRef ctx) {
            UIBezierPath *p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(3, 4)];
            [p addLineToPoint:CGPointMake(9, 10)];
            [p addLineToPoint:CGPointMake(3, 16)];
            p.lineWidth = 2.5;
            p.lineCapStyle = kCGLineCapRound;
            p.lineJoinStyle = kCGLineJoinRound;
            [(self.dark ? RGB(130, 130, 138) : RGB(160, 160, 168)) setStroke];
            [p stroke];
        });
    }];
}

#pragma mark - Fonts

- (UIFont *)titleFont { return [UIFont boldSystemFontOfSize:KCIsPad() ? 16 : 15]; }
- (UIFont *)bodyFont { return [UIFont systemFontOfSize:KCIsPad() ? 15 : 14]; }
- (UIFont *)smallFont { return [UIFont systemFontOfSize:KCIsPad() ? 13 : 12]; }
- (UIFont *)tinyBoldFont { return [UIFont boldSystemFontOfSize:11]; }

- (CGFloat)chatFontSize
{
    switch ([KCSettings chatFontSize]) {
        case 0: return KCIsPad() ? 13 : 12;
        case 2: return KCIsPad() ? 17 : 16;
        default: return KCIsPad() ? 15 : 14;
    }
}

- (UIFont *)chatFont { return [UIFont systemFontOfSize:[self chatFontSize]]; }
- (UIFont *)chatBoldFont { return [UIFont boldSystemFontOfSize:[self chatFontSize]]; }
- (UIFont *)chatSmallFont { return [UIFont systemFontOfSize:[self chatFontSize] - 2]; }

#pragma mark - UIKit

- (UIBarStyle)barStyle { return self.dark ? UIBarStyleBlack : UIBarStyleDefault; }
- (UIStatusBarStyle)statusBarStyle { return self.dark ? UIStatusBarStyleBlackOpaque : UIStatusBarStyleDefault; }
- (UIActivityIndicatorViewStyle)spinnerStyle { return self.dark ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray; }

- (void)applyToNavigationBar:(UINavigationBar *)bar
{
    bar.barStyle = [self barStyle];
    bar.translucent = NO;
    bar.tintColor = nil;
}

- (void)applyToToolbar:(UIToolbar *)bar
{
    bar.barStyle = [self barStyle];
    bar.translucent = NO;
    bar.tintColor = nil;
}

- (void)applyToTabBar:(UITabBar *)bar
{
    // (black glass in both looks; the selected tab lights up green instead of the system blue)
    bar.tintColor = self.dark ? RGB(14, 16, 17) : nil;
    bar.selectedImageTintColor = RGB(83, 252, 24);
}

- (void)applyToTableView:(UITableView *)tableView
{
    tableView.backgroundView = nil;
    tableView.backgroundColor = tableView.style == UITableViewStyleGrouped ? [self backgroundColor] : [self cardColor];
    tableView.separatorColor = [self separatorColor];
    tableView.indicatorStyle = self.dark ? UIScrollViewIndicatorStyleWhite : UIScrollViewIndicatorStyleDefault;
}

- (void)styleCell:(UITableViewCell *)cell
{
    cell.backgroundColor = [self cardColor];
    cell.textLabel.textColor = [self primaryTextColor];
    cell.textLabel.backgroundColor = [UIColor clearColor];
    cell.detailTextLabel.textColor = self.dark ? [self secondaryTextColor] : RGB(56, 84, 135);
    cell.detailTextLabel.backgroundColor = [UIColor clearColor];
    if (self.dark) {
        UIView *selected = [[UIView alloc] init];
        selected.backgroundColor = RGB(50, 50, 55);
        cell.selectedBackgroundView = selected;
    } else {
        cell.selectedBackgroundView = nil;
    }
}

- (void)applyToSearchBar:(UISearchBar *)bar
{
    bar.barStyle = [self barStyle];
    bar.tintColor = nil;
}

@end
