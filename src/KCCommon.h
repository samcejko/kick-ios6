// Shared macros and constants. Everything here must be iOS 6.0 safe.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Any API newer than the iOS 6.0 deployment target is a hard error in files that include this header.
#pragma clang diagnostic error "-Wunguarded-availability"

#define L(key) NSLocalizedString((key), nil)
#define KCIsPad() (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
#define KCLog(fmt, ...) NSLog((@"[Kicker] " fmt), ##__VA_ARGS__)

// Runs a block on the main thread (immediately if already there).
static inline void KCMain(dispatch_block_t block)
{
    if ([NSThread isMainThread]) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

extern NSString * const KCErrorDomain;
extern NSString * const KCThemeDidChangeNotification;
extern NSString * const KCSettingsDidChangeNotification;
extern NSString * const KCFavoritesDidChangeNotification;

// NSError codes in KCErrorDomain (HTTP errors use the HTTP status as code)
enum {
    KCErrorNetwork        = -1,
    KCErrorTLS            = -2,
    KCErrorCertificate    = -3,
    KCErrorTimeout        = -4,
    KCErrorCancelled      = -5,
    KCErrorBadResponse    = -6,
    KCErrorDNS            = -7,
    KCErrorConnect        = -8,
    KCErrorConnectionLost = -9,
    KCErrorAPI            = -10,   // Kick answered, but with an error
    KCErrorOffline        = -11,   // the channel is not live
    KCErrorRestricted     = -12,   // subscribers only, geoblocked...
};

NSError *KCMakeError(NSInteger code, NSString *message);

// JSON values as the type the caller expects, nil/0 for anything else (NSNull, wrong type)
NSString *KCStr(id value);         // numbers become their decimal string
NSDictionary *KCDict(id value);
NSArray *KCArr(id value);
NSInteger KCInt(id value);
double KCDbl(id value);
BOOL KCBool(id value);

// "2026-10-02T17:31:00Z", "2026-10-02T17:31:05.042684Z", "2026-10-02 17:31:00" (all read as UTC)
NSDate *KCDateFromISO(NSString *string);
