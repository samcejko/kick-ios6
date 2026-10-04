#import <Foundation/Foundation.h>
#import "KCTLSSocket.h"

// A small WebSocket client (RFC 6455) on top of the app's own TLS socket - iOS 6 has none of its own.
// Blocking, for one worker thread; -cancel may be called from any thread. Text messages only (what chat servers send).
@interface KCWebSocket : NSObject

@property (nonatomic, readonly) KCTLSSocket *socket;   // for poll(): its descriptor and buffered TLS data

// The TCP/TLS connection (wss:// or ws://) and the HTTP upgrade; YES once the server switched protocols
- (BOOL)connectToURL:(NSURL *)url origin:(NSString *)origin userAgent:(NSString *)userAgent verify:(BOOL)verify error:(NSError **)error;
- (BOOL)sendText:(NSString *)text error:(NSError **)error;

// The text messages completed by what has arrived. Takes frames already received first; only when there are none it
// reads the socket once (call it when poll() said the socket is readable, or when -hasPendingInput is YES). Pings are
// answered here. `closed` turns YES when the server ended the connection.
- (NSArray *)readMessages:(BOOL *)closed error:(NSError **)error;

// A complete frame waits in the buffer, or the TLS layer holds bytes poll() cannot see
- (BOOL)hasPendingInput;

- (void)cancel;
- (void)close;

@end
