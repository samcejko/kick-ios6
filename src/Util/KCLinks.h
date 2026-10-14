#import <UIKit/UIKit.h>

// A web address found in a text
@interface KCTextLink : NSObject
@property (nonatomic, copy) NSString *url;          // with its scheme ("https://" is put before a bare "kick.com/xqc")
@property (nonatomic) NSRange range;                // where it stands in the text (UTF-16 units)
@end

// Web addresses in texts (chat lines, titles, a channel's bio): finding them, and showing them in the link colour.
// An address is "https://…", "www.…", or a bare domain with a well-known ending ("kick.com/xqc", "youtu.be/abc");
// the punctuation around it is not part of it ("(see kick.com/xqc)." gives "kick.com/xqc").
@interface KCLinks : NSObject

+ (NSArray *)linksInText:(NSString *)text;          // KCTextLink, in order (empty when there is none)
+ (NSArray *)urlsInText:(NSString *)text;           // just their URL strings
// The address inside one word (a run without spaces), or {NSNotFound, 0}
+ (NSRange)linkRangeInWord:(NSString *)word;
// The address as a URL string: a scheme is put before a bare one, what has a scheme stays as written
+ (NSString *)urlForLinkText:(NSString *)text;
// The same as NSURL (characters NSURL does not take are percent-encoded); nil when it makes no URL
+ (NSURL *)URLForLinkText:(NSString *)text;
// What to show for an address in a button: without the scheme and "www.", shortened
+ (NSString *)displayTextForURL:(NSURL *)url;

// Shows the text in the label, the addresses in the link colour (the label keeps its font, colour, shadow and
// alignment; `mode` is the line breaking of the paragraphs: word wrapping for a label of several lines). YES when
// the text has an address. Set the label's style first: a label takes the style of an attributed text's start.
+ (BOOL)showText:(NSString *)text inLabel:(UILabel *)label linkColor:(UIColor *)linkColor lineBreakMode:(NSLineBreakMode)mode;

@end
