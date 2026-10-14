#import "KCLinks.h"
#import "KCUtils.h"
#import "KCCommon.h"

@implementation KCTextLink
@end

// The endings a bare address (no scheme, no "www.") is recognised by: the common ones, those of the sites this
// family of apps shows, and this country's. Two-letter endings that are English words ("it", "me", "no", "at")
// are left out: "trust.me" is no link.
static NSSet *KCKnownEndings(void)
{
    static NSSet *endings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        endings = [NSSet setWithArray:@[ @"com", @"net", @"org", @"tv", @"gg", @"be", @"io", @"co", @"eu", @"cz", @"sk", @"de", @"uk",
                                         @"us", @"pl", @"fr", @"es", @"nl", @"ch", @"ru", @"ua", @"br", @"ca", @"au", @"se", @"fi", @"dk",
                                         @"hu", @"ro", @"tr", @"info", @"app", @"dev", @"xyz", @"live", @"stream", @"link", @"ly", @"tube",
                                         @"site", @"online", @"store", @"shop", @"news", @"fm", @"cc", @"ws", @"tech", @"club", @"fun",
                                         @"ai", @"pro", @"biz", @"wiki", @"page", @"media", @"video" ]];
    });
    return endings;
}

static NSCharacterSet *KCHostCharacters(void)
{
    static NSCharacterSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789.-"] invertedSet];
    });
    return set;   // (the characters a host may NOT contain)
}

// A host name (lower case): letters, digits, dots and dashes, at least one dot, nothing odd around the dots.
// `known` asks for one of the endings above (bare addresses); an address with a scheme may end in anything.
static BOOL KCValidHost(NSString *host, BOOL known)
{
    if (host.length < 4 || [host hasPrefix:@"."] || [host hasSuffix:@"."] || [host hasPrefix:@"-"]) return NO;
    if ([host rangeOfString:@".."].location != NSNotFound || [host rangeOfCharacterFromSet:KCHostCharacters()].location != NSNotFound) return NO;
    NSRange dot = [host rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location == NSNotFound || dot.location == 0) return NO;
    NSString *ending = [host substringFromIndex:dot.location + 1];
    if (ending.length < 2) return NO;
    if (known) return [KCKnownEndings() containsObject:ending];
    // (an ending is letters: "1.5" and "192.168.1.1" are numbers, not addresses)
    return [ending rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]].location != NSNotFound;
}

@implementation KCLinks

+ (NSRange)linkRangeInWord:(NSString *)word
{
    NSRange none = NSMakeRange(NSNotFound, 0);
    if (word.length < 4 || [word rangeOfString:@"."].location == NSNotFound) return none;
    // the punctuation around the address: brackets and quotes before it, sentence marks and brackets after it
    static NSCharacterSet *opening, *closing;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        opening = [NSCharacterSet characterSetWithCharactersInString:@"([{<\"'„“‚‘"];
        closing = [NSCharacterSet characterSetWithCharactersInString:@".,;:!?)]}>\"'“”‘’…"];
    });
    NSUInteger start = 0, end = word.length;
    while (start < end && [opening characterIsMember:[word characterAtIndex:start]]) start++;
    while (end > start && [closing characterIsMember:[word characterAtIndex:end - 1]]) {
        // a closing bracket that answers one inside the address stays ("wiki/Foo_(bar)")
        if ([word characterAtIndex:end - 1] == ')' && [[word substringWithRange:NSMakeRange(start, end - start)] rangeOfString:@"("].location != NSNotFound) break;
        end--;
    }
    if (end <= start + 3) return none;
    NSString *lower = [[word substringWithRange:NSMakeRange(start, end - start)] lowercaseString];
    NSString *rest = lower;
    BOOL scheme = NO;
    if ([rest hasPrefix:@"https://"]) { rest = [rest substringFromIndex:8]; scheme = YES; }
    else if ([rest hasPrefix:@"http://"]) { rest = [rest substringFromIndex:7]; scheme = YES; }
    if (!scheme && [rest rangeOfString:@"://"].location != NSNotFound) return none;   // (other schemes are not web links)
    // the host: up to the path, the query, the fragment or a port
    NSRange hostEnd = [rest rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/?#:"]];
    NSString *host = hostEnd.location == NSNotFound ? rest : [rest substringToIndex:hostEnd.location];
    if ([host rangeOfString:@"@"].location != NSNotFound) return none;   // an e-mail address (a "/@handle" in the path is fine)
    // "www.x" alone is nothing; with a scheme any sensible host goes, a bare one needs a known ending
    if (!KCValidHost(host, !scheme && ![host hasPrefix:@"www."])) return none;
    if ([host hasPrefix:@"www."] && [[host substringFromIndex:4] rangeOfString:@"."].location == NSNotFound) return none;
    return NSMakeRange(start, end - start);
}

+ (NSArray *)linksInText:(NSString *)text
{
    NSMutableArray *links = [NSMutableArray array];
    if (!text.length || [text rangeOfString:@"."].location == NSNotFound) return links;
    NSCharacterSet *spaces = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSUInteger n = text.length, pos = 0;
    while (pos < n) {
        if ([spaces characterIsMember:[text characterAtIndex:pos]]) { pos++; continue; }
        NSUInteger end = pos;
        while (end < n && ![spaces characterIsMember:[text characterAtIndex:end]]) end++;
        NSString *word = [text substringWithRange:NSMakeRange(pos, end - pos)];
        NSRange r = [self linkRangeInWord:word];
        if (r.location != NSNotFound) {
            KCTextLink *link = [[KCTextLink alloc] init];
            link.range = NSMakeRange(pos + r.location, r.length);
            link.url = [self urlForLinkText:[word substringWithRange:r]];
            [links addObject:link];
        }
        pos = end;
    }
    return links;
}

+ (NSArray *)urlsInText:(NSString *)text
{
    NSMutableArray *urls = [NSMutableArray array];
    for (KCTextLink *link in [self linksInText:text]) {
        if (link.url.length && ![urls containsObject:link.url]) [urls addObject:link.url];
    }
    return urls;
}

+ (NSString *)urlForLinkText:(NSString *)text
{
    NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!t.length) return nil;
    if ([t rangeOfString:@"://"].location != NSNotFound) return t;
    // (the sites of today all speak https; the plain scheme would only be redirected)
    return [@"https://" stringByAppendingString:t];
}

+ (NSURL *)URLForLinkText:(NSString *)text
{
    NSString *s = [self urlForLinkText:text];
    if (!s.length) return nil;
    NSURL *url = [NSURL URLWithString:s];
    if (!url) {
        // letters outside ASCII, spaces: percent-encoded (the way a browser takes them)
        NSString *escaped = [s stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        url = escaped ? [NSURL URLWithString:escaped] : nil;
    }
    return url.scheme.length ? url : nil;
}

+ (NSString *)displayTextForURL:(NSURL *)url
{
    NSString *s = url.absoluteString ?: @"";
    NSString *lower = [s lowercaseString];
    if ([lower hasPrefix:@"https://"]) s = [s substringFromIndex:8];
    else if ([lower hasPrefix:@"http://"]) s = [s substringFromIndex:7];
    if ([[s lowercaseString] hasPrefix:@"www."]) s = [s substringFromIndex:4];
    if ([s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
    return [KCUtils truncate:s to:60];
}

+ (BOOL)showText:(NSString *)text inLabel:(UILabel *)label linkColor:(UIColor *)linkColor lineBreakMode:(NSLineBreakMode)mode
{
    NSArray *links = [self linksInText:text];
    if (!links.count || !linkColor) {
        label.attributedText = nil;
        label.text = text;
        return NO;
    }
    // the label's own style on the whole text (an attributed text brings its own font and colours, the label's
    // properties no longer apply), the link colour on the addresses
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineBreakMode = mode;
    paragraph.alignment = label.textAlignment;
    NSMutableDictionary *base = [NSMutableDictionary dictionary];
    base[NSFontAttributeName] = label.font ?: [UIFont systemFontOfSize:13];
    base[NSForegroundColorAttributeName] = label.textColor ?: [UIColor blackColor];
    base[NSParagraphStyleAttributeName] = paragraph;
    if (label.shadowColor) {
        NSShadow *shadow = [[NSShadow alloc] init];
        shadow.shadowColor = label.shadowColor;
        shadow.shadowOffset = label.shadowOffset;
        base[NSShadowAttributeName] = shadow;
    }
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:text attributes:base];
    for (KCTextLink *link in links) {
        if (NSMaxRange(link.range) <= s.length) [s addAttribute:NSForegroundColorAttributeName value:linkColor range:link.range];
    }
    label.attributedText = s;
    return YES;
}

@end
