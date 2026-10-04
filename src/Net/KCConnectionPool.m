#import "KCConnectionPool.h"
#import "KCTLSSocket.h"
#import "KCCommon.h"

static const NSTimeInterval KCIdleTimeout = 25;     // most servers drop idle connections after 5 to 60 s
static const NSUInteger KCMaxIdlePerKey = 6;
static const NSUInteger KCMaxIdleTotal = 24;

@interface KCPooledConnection : NSObject
@property (nonatomic, strong) KCTLSSocket *socket;
@property (nonatomic) NSTimeInterval lastUsed;
@end

@implementation KCPooledConnection
@end

@implementation KCConnectionPool {
    NSMutableDictionary *_idle;     // key -> NSMutableArray<KCPooledConnection>
    NSUInteger _count;
    NSUInteger _reuses;
}

+ (instancetype)shared
{
    static KCConnectionPool *pool;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ pool = [[KCConnectionPool alloc] init]; });
    return pool;
}

- (instancetype)init
{
    self = [super init];
    if (self) _idle = [NSMutableDictionary dictionary];
    return self;
}

// Must be called with the lock held. Moves expired connections into `dead`.
- (void)pruneLocked:(NSMutableArray *)dead
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSMutableArray *emptyKeys = [NSMutableArray array];
    for (NSString *key in _idle) {
        NSMutableArray *list = _idle[key];
        for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) {
            KCPooledConnection *c = list[(NSUInteger)i];
            if (now - c.lastUsed > KCIdleTimeout) {
                [dead addObject:c.socket];
                [list removeObjectAtIndex:(NSUInteger)i];
                _count--;
            }
        }
        if (!list.count) [emptyKeys addObject:key];
    }
    [_idle removeObjectsForKeys:emptyKeys];
}

- (KCTLSSocket *)checkoutSocketForKey:(NSString *)key
{
    if (!key) return nil;
    NSMutableArray *dead = [NSMutableArray array];
    KCTLSSocket *result = nil;
    @synchronized (self) {
        [self pruneLocked:dead];
        NSMutableArray *list = _idle[key];
        while (list.count && !result) {
            KCPooledConnection *c = [list lastObject];
            [list removeLastObject];
            _count--;
            if ([c.socket isLikelyAlive]) result = c.socket;
            else [dead addObject:c.socket];
        }
        if (result) _reuses++;
    }
    for (KCTLSSocket *s in dead) [s close];
    return result;
}

- (void)checkinSocket:(KCTLSSocket *)socket forKey:(NSString *)key
{
    if (!socket || !key) return;
    NSMutableArray *dead = [NSMutableArray array];
    @synchronized (self) {
        [self pruneLocked:dead];
        NSMutableArray *list = _idle[key];
        if (!list) {
            list = [NSMutableArray array];
            _idle[key] = list;
        }
        if (list.count >= KCMaxIdlePerKey || _count >= KCMaxIdleTotal) {
            [dead addObject:socket];
        } else {
            KCPooledConnection *c = [[KCPooledConnection alloc] init];
            c.socket = socket;
            c.lastUsed = [NSDate timeIntervalSinceReferenceDate];
            [list addObject:c];
            _count++;
        }
    }
    for (KCTLSSocket *s in dead) [s close];
}

- (void)drain
{
    NSMutableArray *dead = [NSMutableArray array];
    @synchronized (self) {
        for (NSString *key in _idle) {
            for (KCPooledConnection *c in _idle[key]) [dead addObject:c.socket];
        }
        [_idle removeAllObjects];
        _count = 0;
    }
    for (KCTLSSocket *s in dead) [s close];
    if (dead.count) KCLog(@"Connection pool drained (%lu closed)", (unsigned long)dead.count);
}

- (NSUInteger)idleCount
{
    @synchronized (self) { return _count; }
}

- (NSUInteger)reuseCount
{
    @synchronized (self) { return _reuses; }
}

@end
