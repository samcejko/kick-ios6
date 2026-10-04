#import "KCChat.h"
#import "KCWebSocket.h"
#import "KCSettings.h"
#import "KCUtils.h"
#import "KCCommon.h"

#include <poll.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>

// Kick's chat runs on Pusher; the app key is the one kick.com itself uses (public, part of the website)
static NSString * const KCChatURL = @"wss://ws-us2.pusher.com/app/32cbd69e4b950bf97679?protocol=7&client=js&version=8.4.0&flash=false";
static NSString * const KCChatOrigin = @"https://kick.com";
static const NSTimeInterval KCChatIdlePing = 60;         // our own ping when nothing came for this long (the server's limit is 120 s)
static const NSTimeInterval KCChatIdleGiveUp = 150;      // ...and a new connection when still nothing
static const NSTimeInterval KCChatBatchDelay = 0.15;     // messages are handed over in batches this often
static const NSUInteger KCChatBatchMax = 40;

@interface KCChat ()
@property (nonatomic, copy) NSString *channel;
@property (nonatomic, copy) NSString *chatroomId;
@property (nonatomic) KCChatState state;
@property (nonatomic, strong) NSThread *thread;
@property (atomic, strong) KCWebSocket *socket;         // used from the chat thread; -cancel reaches it from the main thread
@property (nonatomic) NSUInteger generation;            // bumped by -disconnect: the thread of an old generation ends
@property (nonatomic) NSInteger attempts;
@end

@implementation KCChat {
    int _wakePipe[2];
}

- (instancetype)initWithChatroomId:(NSString *)chatroomId channel:(NSString *)slug
{
    self = [super init];
    if (self) {
        _chatroomId = [chatroomId copy];
        _channel = [[slug lowercaseString] copy];
        _wakePipe[0] = _wakePipe[1] = -1;
    }
    return self;
}

- (void)dealloc
{
    [self closeWakePipe];
}

- (void)closeWakePipe
{
    if (_wakePipe[0] >= 0) close(_wakePipe[0]);
    if (_wakePipe[1] >= 0) close(_wakePipe[1]);
    _wakePipe[0] = _wakePipe[1] = -1;
}

#pragma mark - Control (main thread)

- (void)connect
{
    if (self.thread) return;
    if (!self.chatroomId.length) return;
    self.generation++;
    self.attempts = 0;
    [self setStateOnMain:KCChatStateConnecting];
    NSUInteger generation = self.generation;
    self.thread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMain:) object:@(generation)];
    self.thread.name = @"KCChat";
    [self.thread start];
}

- (void)disconnect
{
    if (!self.thread) return;
    self.generation++;
    [self.socket cancel];
    [self wake];
    self.thread = nil;
    [self setStateOnMain:KCChatStateDisconnected];
}

- (void)wake
{
    int fd = _wakePipe[1];
    if (fd >= 0) { char c = 1; write(fd, &c, 1); }
}

- (void)setStateOnMain:(KCChatState)state
{
    KCMain(^{
        if (self.state == state) return;
        self.state = state;
        [self.delegate chat:self didChangeState:state];
    });
}

- (void)deliver:(NSArray *)messages
{
    if (!messages.count) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.state == KCChatStateDisconnected) return;
        [self.delegate chat:self didReceiveMessages:messages];
    });
}

#pragma mark - Thread

- (void)threadMain:(NSNumber *)generationNumber
{
    @autoreleasepool {
        NSUInteger generation = generationNumber.unsignedIntegerValue;
        if (pipe(_wakePipe) != 0) {
            _wakePipe[0] = _wakePipe[1] = -1;
        } else {
            // (the drain below must never block: whatever is in the pipe is read, then the read says "nothing")
            fcntl(_wakePipe[0], F_SETFL, fcntl(_wakePipe[0], F_GETFL, 0) | O_NONBLOCK);
        }
        while (generation == self.generation) {
            @autoreleasepool {
                NSError *error = nil;
                BOOL subscribed = [self runConnectionGeneration:generation error:&error];
                if (generation != self.generation) break;
                // the connection ended: wait a while and try again (longer each time, up to a minute)
                self.attempts = subscribed ? 1 : self.attempts + 1;
                NSTimeInterval delay = MIN(2.0 * (1 << MIN(self.attempts, (NSInteger)5)), 60.0);
                if (error) KCLog(@"Chat %@: %@, reconnecting in %.0f s", self.channel, error.localizedDescription, delay);
                [self setStateOnMain:KCChatStateReconnecting];
                [self deliver:@[ [KCChatMessage noticeWithText:L(@"Connection to the chat lost. Reconnecting…")] ]];
                NSDate *until = [NSDate dateWithTimeIntervalSinceNow:delay];
                while (generation == self.generation && [until timeIntervalSinceNow] > 0) usleep(250000);
            }
        }
        [self closeWakePipe];
    }
}

static NSString *KCJSONText(id object)
{
    NSData *data = [KCUtils JSONDataFromObject:object];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

// Pusher wraps an event's payload as a JSON string inside the JSON message
static NSDictionary *KCEventData(id data)
{
    if ([data isKindOfClass:[NSDictionary class]]) return data;
    if ([data isKindOfClass:[NSString class]]) return KCDict([KCUtils JSONObjectFromData:[data dataUsingEncoding:NSUTF8StringEncoding]]);
    return nil;
}

// One connection, until it breaks. Returns YES when the chatroom was subscribed (a real connection, not a failure).
- (BOOL)runConnectionGeneration:(NSUInteger)generation error:(NSError **)error
{
    KCWebSocket *socket = [[KCWebSocket alloc] init];
    self.socket = socket;
    NSString *agent = [NSString stringWithFormat:@"Kicker/%@ (iOS %@)", [KCUtils appVersion], [UIDevice currentDevice].systemVersion];
    if (![socket connectToURL:[NSURL URLWithString:KCChatURL] origin:KCChatOrigin userAgent:agent verify:[KCSettings verifyTLS] error:error]) {
        [socket close];
        self.socket = nil;
        return NO;
    }
    [socket.socket setReadTimeoutMs:20000];
    NSString *channelName = [NSString stringWithFormat:@"chatrooms.%@.v2", self.chatroomId];

    NSMutableArray *batch = [NSMutableArray array];
    NSTimeInterval batchStarted = 0;
    NSTimeInterval lastReceived = [NSDate timeIntervalSinceReferenceDate];
    BOOL subscribed = NO, pinged = NO, ok = YES;

    while (ok && generation == self.generation) {
        @autoreleasepool {
            NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
            // hand over what has gathered
            if (batch.count && (batch.count >= KCChatBatchMax || now - batchStarted >= KCChatBatchDelay)) {
                [self deliver:[batch copy]];
                [batch removeAllObjects];
            }
            // silence from the server: our own ping, then a new connection
            if (now - lastReceived > KCChatIdleGiveUp) {
                if (error) *error = KCMakeError(KCErrorTimeout, @"No data from the chat server");
                ok = NO;
                break;
            }
            if (now - lastReceived > KCChatIdlePing && !pinged) {
                pinged = YES;
                if (![socket sendText:@"{\"event\":\"pusher:ping\",\"data\":{}}" error:error]) { ok = NO; break; }
            }
            // wait for data, a wake-up, or the batch deadline
            if (![socket hasPendingInput]) {
                struct pollfd fds[2] = { { socket.socket.fileDescriptor, POLLIN, 0 }, { _wakePipe[0], POLLIN, 0 } };
                int timeout = batch.count ? (int)MAX(10.0, (KCChatBatchDelay - (now - batchStarted)) * 1000) : 1000;
                int r = poll(fds, _wakePipe[0] >= 0 ? 2 : 1, timeout);
                if (r < 0) {
                    if (errno == EINTR) continue;
                    if (error) *error = KCMakeError(KCErrorConnectionLost, @"poll failed");
                    ok = NO;
                    break;
                }
                if (r == 0) continue;
                if (_wakePipe[0] >= 0 && (fds[1].revents & POLLIN)) {
                    char drain[64];
                    while (read(_wakePipe[0], drain, sizeof(drain)) > 0) {}
                    continue;
                }
                if (fds[0].revents & (POLLERR | POLLHUP | POLLNVAL)) {
                    if (error) *error = KCMakeError(KCErrorConnectionLost, L(@"Connection lost."));
                    ok = NO;
                    break;
                }
                if (!(fds[0].revents & POLLIN)) continue;
            }
            BOOL closed = NO;
            NSError *readError = nil;
            NSArray *texts = [socket readMessages:&closed error:&readError];
            if (texts.count) {
                lastReceived = [NSDate timeIntervalSinceReferenceDate];
                pinged = NO;
            }
            for (NSString *text in texts) {
                NSDictionary *message = KCDict([KCUtils JSONObjectFromData:[text dataUsingEncoding:NSUTF8StringEncoding]]);
                NSString *event = KCStr(message[@"event"]);
                if (!event.length) continue;
                NSDictionary *data = KCEventData(message[@"data"]);
                if ([event isEqualToString:@"pusher:connection_established"]) {
                    NSDictionary *subscribe = @{ @"event": @"pusher:subscribe", @"data": @{ @"auth": @"", @"channel": channelName } };
                    if (![socket sendText:KCJSONText(subscribe) error:error]) { ok = NO; break; }
                } else if ([event isEqualToString:@"pusher_internal:subscription_succeeded"]) {
                    if (!subscribed) {
                        subscribed = YES;
                        self.attempts = 0;
                        [self setStateOnMain:KCChatStateConnected];
                    }
                } else if ([event isEqualToString:@"pusher:ping"]) {
                    if (![socket sendText:@"{\"event\":\"pusher:pong\",\"data\":{}}" error:error]) { ok = NO; break; }
                } else if ([event isEqualToString:@"pusher:error"]) {
                    KCLog(@"Chat %@: server error %@", self.channel, KCJSONText(data) ?: @"");
                } else {
                    KCChatMessage *m = [self handleEvent:event data:data];
                    if (m) {
                        if (!batch.count) batchStarted = [NSDate timeIntervalSinceReferenceDate];
                        [batch addObject:m];
                    }
                }
            }
            if (!ok) break;
            if (closed) {
                if (error) *error = readError ?: KCMakeError(KCErrorConnectionLost, L(@"The chat server closed the connection."));
                ok = NO;
                break;
            }
        }
    }
    if (batch.count) [self deliver:[batch copy]];
    [socket close];
    self.socket = nil;
    return subscribed;
}

// Kick's chat events: a message to show, or something the delegate hears about (returns nil then)
- (KCChatMessage *)handleEvent:(NSString *)event data:(NSDictionary *)data
{
    if ([event isEqualToString:@"App\\Events\\ChatMessageEvent"]) {
        return [KCChatMessage messageFromKick:data];
    }
    if ([event isEqualToString:@"App\\Events\\MessageDeletedEvent"]) {
        NSString *messageId = KCStr(KCDict(data[@"message"])[@"id"]) ?: KCStr(data[@"id"]);
        if (messageId.length) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(chat:didDeleteMessageWithId:)]) [self.delegate chat:self didDeleteMessageWithId:messageId];
            });
        }
        return nil;
    }
    if ([event isEqualToString:@"App\\Events\\UserBannedEvent"]) {
        NSDictionary *user = KCDict(data[@"user"]);
        NSString *slug = [(KCStr(user[@"slug"]) ?: KCStr(user[@"username"])) lowercaseString];
        // (a timeout carries its length in minutes; a permanent ban none)
        NSInteger seconds = KCBool(data[@"permanent"]) ? 0 : KCInt(data[@"duration"]) * 60;
        if (slug.length) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(chat:didClearMessagesOfUser:seconds:)]) [self.delegate chat:self didClearMessagesOfUser:slug seconds:seconds];
            });
        }
        return nil;
    }
    if ([event isEqualToString:@"App\\Events\\ChatroomClearEvent"]) {
        // (the chat view greys the lines out and says so itself)
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(chat:didClearMessagesOfUser:seconds:)]) [self.delegate chat:self didClearMessagesOfUser:nil seconds:0];
        });
        return nil;
    }
    if ([event isEqualToString:@"App\\Events\\ChatroomUpdatedEvent"]) {
        NSMutableDictionary *state = [NSMutableDictionary dictionary];
        NSDictionary *slow = KCDict(data[@"slow_mode"]), *followers = KCDict(data[@"followers_mode"]);
        NSDictionary *subscribers = KCDict(data[@"subscribers_mode"]), *emotes = KCDict(data[@"emotes_mode"]);
        if (slow) state[@"slow"] = @(KCBool(slow[@"enabled"]) ? KCInt(slow[@"message_interval"]) : 0);
        if (followers) state[@"followersOnly"] = @(KCBool(followers[@"enabled"]) ? KCInt(followers[@"min_duration"]) : -1);
        if (subscribers) state[@"subscribersOnly"] = @(KCBool(subscribers[@"enabled"]));
        if (emotes) state[@"emoteOnly"] = @(KCBool(emotes[@"enabled"]));
        if (state.count) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(chat:didUpdateRoomState:)]) [self.delegate chat:self didUpdateRoomState:state];
            });
        }
        return nil;
    }
    if ([event isEqualToString:@"App\\Events\\SubscriptionEvent"]) {
        NSString *who = KCStr(data[@"username"]);
        NSInteger months = KCInt(data[@"months"]);
        if (!who.length) return nil;
        NSString *text = months > 1 ? [NSString stringWithFormat:L(@"%@ subscribed for %ld months"), who, (long)months]
                                    : [NSString stringWithFormat:L(@"%@ subscribed"), who];
        return [KCChatMessage userNoticeWithText:text type:@"sub"];
    }
    if ([event isEqualToString:@"App\\Events\\GiftedSubscriptionsEvent"]) {
        NSString *who = KCStr(data[@"gifter_username"]);
        NSUInteger count = KCArr(data[@"gifted_usernames"]).count;
        if (!who.length || !count) return nil;
        NSString *text = [NSString stringWithFormat:L(@"%@ gifted %lu subscriptions"), who, (unsigned long)count];
        return [KCChatMessage userNoticeWithText:text type:@"subgift"];
    }
    if ([event isEqualToString:@"App\\Events\\StreamHostEvent"]) {
        NSString *who = KCStr(data[@"host_username"]);
        NSInteger viewers = KCInt(data[@"number_viewers"]);
        if (!who.length) return nil;
        NSString *text = [NSString stringWithFormat:L(@"%@ is hosting with %@"), who, [KCUtils formatViewers:viewers]];
        return [KCChatMessage userNoticeWithText:text type:@"host"];
    }
    return nil;
}

@end
