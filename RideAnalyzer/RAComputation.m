//
//  RAComputation.m
//  RideAnalyzer
//

#import "RAComputation.h"

@interface RACancellation ()
/// set by RAComputation: shows an intermediate result on the main thread
@property (copy, nullable) void (^partialHandler)(id result);
@end

@implementation RACancellation
{
    BOOL _cancelled;
}

- (void)deliverPartialResult:(id)result
{
    void (^handler)(id) = self.partialHandler;
    if (handler && !self.cancelled) handler(result);
}

- (BOOL)isCancelled
{
    @synchronized (self) {
        return _cancelled;
    }
}

- (void)cancel
{
    @synchronized (self) {
        _cancelled = YES;
    }
}

@end

@implementation RAComputation
{
    dispatch_queue_t _queue;
    RACancellation *_current;
}

- (instancetype)initWithLabel:(NSString *)label
{
    self = [super init];
    if (self) {
        NSString *name = [@"com.banyanshade.RideAnalyzer.computation." stringByAppendingString:label];
        _queue = dispatch_queue_create(name.UTF8String,
                                       dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
    }
    return self;
}

- (instancetype)init
{
    return [self initWithLabel:@"default"];
}

- (void)dealloc
{
    [_current cancel];
}

- (BOOL)isRunning
{
    return _current != nil;
}

- (void)notifyRunning:(BOOL)running
{
    if (self.runningHandler) self.runningHandler(running);
}

- (void)start:(RAComputationWork)work completion:(void (^)(id _Nullable))completion
{
    [self start:work partial:nil completion:completion];
}

- (void)start:(RAComputationWork)work partial:(nullable void (^)(id))partial completion:(void (^)(id _Nullable))completion
{
    NSAssert(NSThread.isMainThread, @"RAComputation: start on the main thread");
    BOOL wasRunning = _current != nil;
    if (_current) {
        [_current cancel];
        _cancelledCount++;
    }
    RACancellation *token = [[RACancellation alloc] init];
    _current = token;
    _startedCount++;
    if (partial) {
        // the latest intermediate result waits for the main thread; older ones not shown yet are dropped
        __weak RAComputation *weakComputation = self;
        void (^show)(id) = [partial copy];
        NSMutableArray *pending = [NSMutableArray array];
        token.partialHandler = ^(id result) {
            @synchronized (pending) {
                [pending removeAllObjects];
                [pending addObject:result];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                RAComputation *me = weakComputation;
                id latest = nil;
                @synchronized (pending) {
                    latest = pending.firstObject;
                    [pending removeAllObjects];
                }
                if (!me || !latest || token.cancelled || me->_current != token) return;
                me->_partialCount++;
                show(latest);
            });
        };
    }
    if (!wasRunning) [self notifyRunning:YES];
    __weak RAComputation *weakSelf = self;
    RAComputationWork job = [work copy];
    void (^done)(id) = [completion copy];
    dispatch_block_t run = ^{
        if (token.cancelled) {
            token.partialHandler = nil;     // (it holds the token)
            return;
        }
        id result = job(token);
        token.partialHandler = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            RAComputation *me = weakSelf;
            if (!me || token.cancelled || me->_current != token) return;   // replaced or cancelled meanwhile
            me->_current = nil;
            me->_finishedCount++;
            [me notifyRunning:NO];
            done(result);
        });
    };
    if (self.delay > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.delay * NSEC_PER_SEC)), _queue, run);
    } else {
        dispatch_async(_queue, run);
    }
}

- (void)cancel
{
    NSAssert(NSThread.isMainThread, @"RAComputation: cancel on the main thread");
    if (!_current) return;
    [_current cancel];
    _current = nil;
    _cancelledCount++;
    [self notifyRunning:NO];
}

@end
