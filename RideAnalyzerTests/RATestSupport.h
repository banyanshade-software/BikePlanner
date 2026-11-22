//
//  RATestSupport.h
//  RideAnalyzerTests
//
//  Shared helpers of the Ride Analyzer tests (#82): waiting, ride files (TCX, GPX, FIT) and a stub of the Garmin
//  Connect Personal API (an NSURLProtocol given to the client's session: nothing goes to the network).
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

/// runs the main run loop until the condition holds or the timeout passes; YES if it holds
BOOL RAWaitUntil(NSTimeInterval timeout, BOOL (^condition)(void));

/// ~1.1 km north per point, 10 minutes apart, from 2026-11-18 + start seconds, altitudes as given
NSArray<CLLocation *> *RATrace(NSArray<NSNumber *> *altitudes, NSTimeInterval start);

/// a TCX activity of that trace; deviceName / unitID: its Creator, if not nil
NSData *RATCX(NSArray<NSNumber *> *altitudes, NSTimeInterval start, NSString * _Nullable deviceName,
              NSNumber * _Nullable unitID);
/// a GPX track of that trace with <time>
NSData *RAGPX(NSArray<NSNumber *> *altitudes, NSTimeInterval start);
/// a FIT activity of that trace: file_id (Garmin, product, serial), records, a session with sport cycling
NSData *RAFIT(NSArray<NSNumber *> *altitudes, NSTimeInterval start, uint16_t product, uint32_t serial);
/// the same, with the total_ascent of the session (the gain computed by the device), 0: none
NSData *RAFITWithAscent(NSArray<NSNumber *> *altitudes, NSTimeInterval start, uint16_t product, uint32_t serial,
                        uint16_t totalAscent);

/// a ZIP archive holding one file, stored or deflated
NSData *RAZip(NSString *name, NSData *content, BOOL deflate);

/// a JWT whose exp claim is that date (not signed)
NSString *RAJWT(NSDate *expiry);

/// what the stub answers for a request
@interface RAStubResponse : NSObject
@property (nonatomic) NSInteger status;
@property (nonatomic) NSData *body;
+ (instancetype)status:(NSInteger)status body:(nullable NSData *)body;
+ (instancetype)json:(id)object;
@end

/// the Garmin Connect stub: handler decides the answer, every request is recorded
@interface RAStubURLProtocol : NSURLProtocol
@property (class, nonatomic, copy, nullable) RAStubResponse * _Nullable (^handler)(NSURLRequest *request);
@property (class, readonly, nonatomic) NSArray<NSURLRequest *> *requests;
+ (void)reset;
/// a session whose requests go to the stub
+ (NSURLSession *)session;
@end

NS_ASSUME_NONNULL_END
