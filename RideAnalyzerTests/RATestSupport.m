//
//  RATestSupport.m
//  RideAnalyzerTests
//

#import "RATestSupport.h"
#import "BPFITBuilder.h"
#import <compression.h>

BOOL RAWaitUntil(NSTimeInterval timeout, BOOL (^condition)(void))
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition()) {
        if ([end timeIntervalSinceNow] < 0) return NO;
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return YES;
}

static const NSTimeInterval RAEpoch = 1795478400; // 2026-11-18 00:00 UTC

NSArray<CLLocation *> *RATrace(NSArray<NSNumber *> *altitudes, NSTimeInterval start)
{
    NSMutableArray<CLLocation *> *trace = [NSMutableArray array];
    for (NSUInteger i = 0; i < altitudes.count; i++) {
        [trace addObject:[[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(45.0 + 0.01 * i, 5.0)
            altitude:altitudes[i].doubleValue horizontalAccuracy:5 verticalAccuracy:5
            timestamp:[NSDate dateWithTimeIntervalSince1970:RAEpoch + start + 600 * i]]];
    }
    return trace;
}

NSData *RATCX(NSArray<NSNumber *> *altitudes, NSTimeInterval start, NSString *deviceName, NSNumber *unitID)
{
    NSISO8601DateFormatter *iso = [[NSISO8601DateFormatter alloc] init];
    NSArray<CLLocation *> *trace = RATrace(altitudes, start);
    NSString *t0 = [iso stringFromDate:trace.firstObject.timestamp];
    NSMutableString *xml = [NSMutableString stringWithFormat:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<TrainingCenterDatabase xmlns=\"http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2\">"
        @"<Activities><Activity Sport=\"Biking\"><Id>%@</Id><Lap StartTime=\"%@\"><Track>", t0, t0];
    for (CLLocation *l in trace) {
        [xml appendFormat:@"<Trackpoint><Time>%@</Time><Position><LatitudeDegrees>%.6f</LatitudeDegrees>"
         @"<LongitudeDegrees>%.6f</LongitudeDegrees></Position><AltitudeMeters>%.1f</AltitudeMeters></Trackpoint>",
         [iso stringFromDate:l.timestamp], l.coordinate.latitude, l.coordinate.longitude, l.altitude];
    }
    [xml appendString:@"</Track></Lap>"];
    if (deviceName || unitID) {
        [xml appendString:@"<Creator>"];
        if (deviceName) [xml appendFormat:@"<Name>%@</Name>", deviceName];
        if (unitID) [xml appendFormat:@"<UnitId>%@</UnitId><ProductID>3122</ProductID>", unitID];
        [xml appendString:@"</Creator>"];
    }
    [xml appendString:@"</Activity></Activities></TrainingCenterDatabase>"];
    return [xml dataUsingEncoding:NSUTF8StringEncoding];
}

NSData *RAGPX(NSArray<NSNumber *> *altitudes, NSTimeInterval start)
{
    NSISO8601DateFormatter *iso = [[NSISO8601DateFormatter alloc] init];
    NSMutableString *xml = [NSMutableString stringWithString:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"test\""
        @" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><trkseg>\n"];
    for (CLLocation *l in RATrace(altitudes, start)) {
        [xml appendFormat:@"<trkpt lat=\"%.6f\" lon=\"%.6f\"><ele>%.1f</ele><time>%@</time></trkpt>\n",
         l.coordinate.latitude, l.coordinate.longitude, l.altitude, [iso stringFromDate:l.timestamp]];
    }
    [xml appendString:@"</trkseg></trk></gpx>\n"];
    return [xml dataUsingEncoding:NSUTF8StringEncoding];
}

NSData *RAFIT(NSArray<NSNumber *> *altitudes, NSTimeInterval start, uint16_t product, uint32_t serial)
{
    NSArray<CLLocation *> *trace = RATrace(altitudes, start);
    BPFITBuilder *b = [[BPFITBuilder alloc] init];
    [b defineLocal:0 global:0 fields:@[ @[ @0, @1, @(BPFITEnum) ], @[ @1, @2, @(BPFITUInt16) ], @[ @2, @2, @(BPFITUInt16) ],
                                         @[ @3, @4, @(BPFITUInt32z) ] ]];
    [b dataLocal:0 values:@[ @4, @1, @(product), @(serial) ]];
    [b defineLocal:1 global:20 fields:@[ @[ @253, @4, @(BPFITUInt32) ], @[ @0, @4, @(BPFITSInt32) ],
                                         @[ @1, @4, @(BPFITSInt32) ], @[ @2, @2, @(BPFITUInt16) ] ]];
    for (CLLocation *l in trace) {
        [b dataLocal:1 values:@[ @([BPFITBuilder fitTimestamp:l.timestamp]),
                                 @([BPFITBuilder semicircles:l.coordinate.latitude]),
                                 @([BPFITBuilder semicircles:l.coordinate.longitude]),
                                 @(lround((l.altitude + 500) * 5)) ]];
    }
    [b defineLocal:2 global:18 fields:@[ @[ @253, @4, @(BPFITUInt32) ], @[ @5, @1, @(BPFITEnum) ] ]];
    [b dataLocal:2 values:@[ @([BPFITBuilder fitTimestamp:trace.lastObject.timestamp]), @2 ]];
    return b.data;
}

static uint32_t RACRC32(NSData *data)
{
    uint32_t crc = 0xFFFFFFFF;
    const uint8_t *p = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        crc ^= p[i];
        for (int k = 0; k < 8; k++) crc = (crc >> 1) ^ (0xEDB88320 & (0 - (crc & 1)));
    }
    return ~crc;
}

static void RAAppend(NSMutableData *d, uint32_t v, NSUInteger size)
{
    for (NSUInteger i = 0; i < size; i++) {
        uint8_t byte = (uint8_t)(v >> (8 * i));
        [d appendBytes:&byte length:1];
    }
}

NSData *RAZip(NSString *name, NSData *content, BOOL deflate)
{
    NSData *stored = content;
    if (deflate) {
        NSMutableData *out = [NSMutableData dataWithLength:content.length + 1024];
        size_t n = compression_encode_buffer(out.mutableBytes, out.length, content.bytes, content.length, NULL,
                                             COMPRESSION_ZLIB);
        out.length = n;
        stored = out;
    }
    NSData *nameData = [name dataUsingEncoding:NSUTF8StringEncoding];
    uint32_t crc = RACRC32(content);
    NSMutableData *zip = [NSMutableData data];
    // local file header
    RAAppend(zip, 0x04034b50, 4); RAAppend(zip, 20, 2); RAAppend(zip, 0, 2); RAAppend(zip, deflate ? 8 : 0, 2);
    RAAppend(zip, 0, 2); RAAppend(zip, 0, 2); RAAppend(zip, crc, 4);
    RAAppend(zip, (uint32_t)stored.length, 4); RAAppend(zip, (uint32_t)content.length, 4);
    RAAppend(zip, (uint32_t)nameData.length, 2); RAAppend(zip, 0, 2);
    [zip appendData:nameData];
    [zip appendData:stored];
    // central directory
    uint32_t cdOffset = (uint32_t)zip.length;
    RAAppend(zip, 0x02014b50, 4); RAAppend(zip, 20, 2); RAAppend(zip, 20, 2); RAAppend(zip, 0, 2);
    RAAppend(zip, deflate ? 8 : 0, 2); RAAppend(zip, 0, 2); RAAppend(zip, 0, 2); RAAppend(zip, crc, 4);
    RAAppend(zip, (uint32_t)stored.length, 4); RAAppend(zip, (uint32_t)content.length, 4);
    RAAppend(zip, (uint32_t)nameData.length, 2); RAAppend(zip, 0, 2); RAAppend(zip, 0, 2);
    RAAppend(zip, 0, 2); RAAppend(zip, 0, 2); RAAppend(zip, 0, 4); RAAppend(zip, 0, 4);
    [zip appendData:nameData];
    uint32_t cdSize = (uint32_t)zip.length - cdOffset;
    // end of central directory
    RAAppend(zip, 0x06054b50, 4); RAAppend(zip, 0, 2); RAAppend(zip, 0, 2); RAAppend(zip, 1, 2); RAAppend(zip, 1, 2);
    RAAppend(zip, cdSize, 4); RAAppend(zip, cdOffset, 4); RAAppend(zip, 0, 2);
    return zip;
}

NSString *RAJWT(NSDate *expiry)
{
    NSString *(^b64)(NSData *) = ^NSString *(NSData *d) {
        NSString *s = [d base64EncodedStringWithOptions:0];
        s = [[s stringByReplacingOccurrencesOfString:@"+" withString:@"-"] stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
        return [s stringByReplacingOccurrencesOfString:@"=" withString:@""];
    };
    NSData *header = [@"{\"alg\":\"none\",\"typ\":\"JWT\"}" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *claims = [NSJSONSerialization dataWithJSONObject:@{ @"exp": @((long long)expiry.timeIntervalSince1970) }
                                                     options:0 error:NULL];
    return [NSString stringWithFormat:@"%@.%@.sig", b64(header), b64(claims)];
}

@implementation RAStubResponse

+ (instancetype)status:(NSInteger)status body:(nullable NSData *)body
{
    RAStubResponse *r = [[RAStubResponse alloc] init];
    r.status = status;
    r.body = body ?: [NSData data];
    return r;
}

+ (instancetype)json:(id)object
{
    return [self status:200 body:[NSJSONSerialization dataWithJSONObject:object options:0 error:NULL]];
}

@end

static RAStubResponse * _Nullable (^RAStubHandler)(NSURLRequest *);
static NSMutableArray<NSURLRequest *> *RAStubRequests;

@implementation RAStubURLProtocol

+ (RAStubResponse * _Nullable (^)(NSURLRequest *))handler
{
    return RAStubHandler;
}

+ (void)setHandler:(RAStubResponse * _Nullable (^)(NSURLRequest *))handler
{
    @synchronized (self) {
        RAStubHandler = [handler copy];
    }
}

+ (NSArray<NSURLRequest *> *)requests
{
    @synchronized (self) {
        return [RAStubRequests copy] ?: @[];
    }
}

+ (void)reset
{
    @synchronized (self) {
        RAStubHandler = nil;
        RAStubRequests = [NSMutableArray array];
    }
}

+ (NSURLSession *)session
{
    NSURLSessionConfiguration *c = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    c.protocolClasses = @[ [RAStubURLProtocol class] ];
    return [NSURLSession sessionWithConfiguration:c];
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

- (void)startLoading
{
    RAStubResponse * _Nullable (^handler)(NSURLRequest *);
    @synchronized ([RAStubURLProtocol class]) {
        if (!RAStubRequests) RAStubRequests = [NSMutableArray array];
        [RAStubRequests addObject:self.request];
        handler = RAStubHandler;
    }
    RAStubResponse *r = handler ? handler(self.request) : nil;
    if (!r) r = [RAStubResponse status:404 body:nil];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:(NSURL *)self.request.URL statusCode:r.status
                                                             HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:r.body];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading
{
}

@end
