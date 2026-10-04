#import <Foundation/Foundation.h>

typedef void (^KCHTTPCompletion)(NSInteger status, NSData *body, NSDictionary *headers, NSError *error);
typedef void (^KCJSONCompletion)(id json, NSInteger status, NSError *error);

// A running request of KCHTTP. After -cancel the completion block is never called.
@interface KCHTTPTask : NSObject
@property (atomic, readonly) BOOL isCancelled;
@property (atomic, copy) dispatch_block_t cancelBlock;   // for chained requests: called by -cancel (once)
- (void)cancel;
@end

// Convenience layer over KCHTTPRequest for API calls: redirects are followed, GET requests are tried a second
// time after a network error, completion blocks run on the main thread.
@interface KCHTTP : NSObject

+ (KCHTTPTask *)request:(NSString *)method url:(NSString *)url headers:(NSDictionary *)headers body:(NSData *)body
                retries:(NSInteger)retries completion:(KCHTTPCompletion)completion;

+ (KCHTTPTask *)get:(NSString *)url headers:(NSDictionary *)headers completion:(KCHTTPCompletion)completion;

// JSON answers. `error` is set for network errors, for statuses >= 400 (code = the status, message from the body
// when it has one) and for bodies that are not JSON; `json` is passed even with an error when the body parsed.
+ (KCHTTPTask *)getJSON:(NSString *)url headers:(NSDictionary *)headers completion:(KCJSONCompletion)completion;
+ (KCHTTPTask *)postJSON:(NSString *)url headers:(NSDictionary *)headers object:(id)object retries:(NSInteger)retries
              completion:(KCJSONCompletion)completion;
+ (KCHTTPTask *)postForm:(NSString *)url fields:(NSDictionary *)fields completion:(KCJSONCompletion)completion;

@end
