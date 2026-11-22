//
//  RAComputation.h
//  RideAnalyzer
//
//  Asynchronous computations of the views (#82, owner's request 2026-11-22: "a mechanism of asynchronous
//  computation / display, cancelled when the parameters or the selection change").
//
//  Each view that computes something from the selection or its settings (ride detail, trends, map, climbs) owns an
//  RAComputation: -start:completion: cancels the computation in progress, if any, and runs the new one in the
//  background (one at a time per view: a serial queue). The work receives an RACancellation and checks it between
//  its steps (or in its loops) to stop early; its result is shown (the completion, on the main thread) only if it
//  is still the latest one. `delay` lets quick successive changes (typing in the search field, dragging a slider)
//  compute once. `runningHandler` tells the view when to show its spinner.
//
//  The work runs off the main thread: it must not touch views, and should read snapshots taken on the main thread
//  (copies of the equipment, arrays of rides — whose properties read in the background are atomic).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// a flag the work checks: set by -[RAComputation cancel] or a newer -start:completion: (thread-safe)
@interface RACancellation : NSObject
@property (readonly, getter=isCancelled) BOOL cancelled;
- (void)cancel;
/// from the work, any thread: an intermediate result, shown (the partial block of -start:partial:completion:, on the
/// main thread) unless cancelled meanwhile or a later one is already waiting; ignored without a partial block
- (void)deliverPartialResult:(id)result;
@end

typedef id _Nullable (^RAComputationWork)(RACancellation *cancellation);

@interface RAComputation : NSObject

- (instancetype)initWithLabel:(NSString *)label;

/// seconds to wait before starting the work (0 by default): a newer start within that time replaces it
@property (nonatomic) NSTimeInterval delay;
/// a computation is in progress (started and neither finished nor cancelled)
@property (readonly, nonatomic, getter=isRunning) BOOL running;
/// on the main thread, when `running` changes (not between a cancelled computation and its replacement)
@property (copy, nonatomic, nullable) void (^runningHandler)(BOOL running);
/// how many computations were started / finished and shown / cancelled (tests, diagnostics)
@property (readonly, nonatomic) NSUInteger startedCount, finishedCount, cancelledCount;

/// cancels the computation in progress and starts this one; the completion runs on the main thread with the result,
/// unless it was cancelled meanwhile. Call on the main thread.
- (void)start:(RAComputationWork)work completion:(void (^)(id _Nullable result))completion;
/// the same, with intermediate results (a long computation shows as it goes): partial runs on the main thread for
/// each result the work delivers, before the completion, never after it nor once cancelled
- (void)start:(RAComputationWork)work partial:(nullable void (^)(id result))partial
   completion:(void (^)(id _Nullable result))completion;
@property (readonly, nonatomic) NSUInteger partialCount;   // intermediate results shown (tests)
/// cancels the computation in progress (its completion will not run). Call on the main thread.
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
