//
//  BPStubServer.m
//  BikePlannerTests (shared with BikePlannerUITests)
//

#import "BPStubServer.h"
#import <Network/Network.h>
#import <objc/runtime.h>
#import <math.h>

@implementation BPStubRequest
@end


#pragma mark - in-process transport

static NSString * const kBPStubHost = @"bpstub.test";
static __weak BPStubServer *bpInProcessServer = nil;

@interface BPStubServer (InProcess)
- (NSInteger) handle:(BPStubRequest *)req contentType:(NSString **)ctype body:(NSData **)body;
@end

// Serves requests to http://bpstub.test/… from the in-process stub server, without any socket.
@interface BPStubURLProtocol : NSURLProtocol
@end

@implementation BPStubURLProtocol

+ (BOOL) canInitWithRequest:(NSURLRequest *)request
{
    return bpInProcessServer && [request.URL.host isEqualToString:kBPStubHost];
}

+ (NSURLRequest *) canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

+ (NSData *) bodyOf:(NSURLRequest *)request
{
    if (request.HTTPBody) return request.HTTPBody;
    NSInputStream *in = request.HTTPBodyStream;
    if (!in) return [NSData data];
    NSMutableData *d = [NSMutableData data];
    uint8_t buf[4096];
    [in open];
    NSInteger n;
    while ((n = [in read:buf maxLength:sizeof(buf)]) > 0) [d appendBytes:buf length:(NSUInteger)n];
    [in close];
    return d;
}

- (void) startLoading
{
    BPStubServer *server = bpInProcessServer;
    if (!server) {
        // stopped between canInitWithRequest: and now (request started by the app after the test ended)
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                                           code:NSURLErrorCannotConnectToHost
                                                                       userInfo:nil]];
        return;
    }
    NSURLComponents *c = [NSURLComponents componentsWithURL:self.request.URL resolvingAgainstBaseURL:NO];
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *it in c.queryItems) q[it.name] = it.value ?: @"";
    BPStubRequest *req = [BPStubRequest new];
    req.method = self.request.HTTPMethod ?: @"GET";
    req.path = c.path.length ? c.path : @"/";
    req.query = q;
    req.body = [[NSString alloc] initWithData:[[self class] bodyOf:self.request] encoding:NSUTF8StringEncoding] ?: @"";

    NSString *ctype = nil;
    NSData *body = nil;
    NSInteger status = [server handle:req contentType:&ctype body:&body];
    NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:status
                                                         HTTPVersion:@"HTTP/1.1"
                                                        headerFields:@{ @"Content-Type": ctype }];
    void (^deliver)(void) = ^{
        [self.client URLProtocol:self didReceiveResponse:resp cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:body];
        [self.client URLProtocolDidFinishLoading:self];
    };
    double delay = server.responseDelay;
    if (delay > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), deliver);
    } else {
        deliver();
    }
}

- (void) stopLoading
{
}

// Sessions created from +defaultSessionConfiguration (e.g. BRouterClient) do not consult the
// globally registered NSURLProtocols: add ours to every default configuration (test process only;
// it ignores requests unless an in-process server is running).
+ (void) installInDefaultSessionConfiguration
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class meta = object_getClass([NSURLSessionConfiguration class]);
        Method m = class_getClassMethod([NSURLSessionConfiguration class], @selector(defaultSessionConfiguration));
        IMP original = method_getImplementation(m);
        IMP replacement = imp_implementationWithBlock(^NSURLSessionConfiguration *(id cls) {
            NSURLSessionConfiguration *c = ((NSURLSessionConfiguration *(*)(id, SEL))original)(cls, @selector(defaultSessionConfiguration));
            c.protocolClasses = [@[[BPStubURLProtocol class]] arrayByAddingObjectsFromArray:c.protocolClasses ?: @[]];
            return c;
        });
        class_replaceMethod(meta, @selector(defaultSessionConfiguration), replacement, method_getTypeEncoding(m));
    });
}

@end


@implementation BPStubServer {
    nw_listener_t _listener;
    dispatch_queue_t _queue;
    NSMutableArray<BPStubRequest *> *_requests;
    BOOL _inProcess;
}

- (instancetype) init
{
    self = [super init];
    if (self) {
        _requests = [NSMutableArray array];
        _failStatus = 500;
        _queue = dispatch_queue_create("BPStubServer", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void) dealloc
{
    [self stop];
}

#pragma mark - lifecycle

- (BOOL) start
{
    nw_parameters_t params = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,
                                                             NW_PARAMETERS_DEFAULT_CONFIGURATION);
    nw_parameters_set_local_endpoint(params, nw_endpoint_create_host("127.0.0.1", "0"));
    _listener = nw_listener_create(params);
    if (!_listener) return NO;

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block BOOL ready = NO;
    nw_listener_set_queue(_listener, _queue);
    nw_listener_set_state_changed_handler(_listener, ^(nw_listener_state_t state, nw_error_t error) {
        if (state == nw_listener_state_ready) {
            ready = YES;
            dispatch_semaphore_signal(sem);
        } else if (state == nw_listener_state_failed) {
            dispatch_semaphore_signal(sem);
        }
    });
    __weak BPStubServer *weakSelf = self;
    nw_listener_set_new_connection_handler(_listener, ^(nw_connection_t conn) {
        [weakSelf handleConnection:conn];
    });
    nw_listener_start(_listener);
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    if (!ready) return NO;
    _port = nw_listener_get_port(_listener);
    return _port != 0;
}

- (BOOL) startInProcess
{
    _inProcess = YES;
    bpInProcessServer = self;
    [NSURLProtocol registerClass:[BPStubURLProtocol class]];
    [BPStubURLProtocol installInDefaultSessionConfiguration];
    return YES;
}

- (void) stop
{
    if (_inProcess && bpInProcessServer == self) {
        bpInProcessServer = nil;
        [NSURLProtocol unregisterClass:[BPStubURLProtocol class]];
    }
    _inProcess = NO;
    if (_listener) {
        nw_listener_cancel(_listener);
        _listener = nil;
    }
}

- (NSURL *) baseURL
{
    if (_inProcess) return [NSURL URLWithString:[@"http://" stringByAppendingString:kBPStubHost]];
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u", _port]];
}

- (NSURL *) overpassURL
{
    return [self.baseURL URLByAppendingPathComponent:@"api/interpreter"];
}

#pragma mark - requests log

- (NSArray<BPStubRequest *> *) requests
{
    @synchronized (_requests) {
        return [_requests copy];
    }
}

- (NSArray<BPStubRequest *> *) requestsWithPath:(NSString *)path
{
    return [self.requests filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"path == %@", path]];
}

- (void) clearRequests
{
    @synchronized (_requests) {
        [_requests removeAllObjects];
    }
}

#pragma mark - HTTP

- (void) handleConnection:(nw_connection_t)conn
{
    nw_connection_set_queue(conn, _queue);
    nw_connection_start(conn);
    [self receiveOn:conn buffer:[NSMutableData data]];
}

- (void) receiveOn:(nw_connection_t)conn buffer:(NSMutableData *)buf
{
    nw_connection_receive(conn, 1, 1 << 20, ^(dispatch_data_t content, nw_content_context_t ctx, bool complete, nw_error_t error) {
        if (content) {
            dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t offset, const void *bytes, size_t size) {
                [buf appendBytes:bytes length:size];
                return true;
            });
        }
        BPStubRequest *req = [self parseRequest:buf];
        if (req) {
            [self respondTo:req on:conn];
        } else if (error || complete) {
            nw_connection_cancel(conn);
        } else {
            [self receiveOn:conn buffer:buf];
        }
    });
}

// returns nil while the request is incomplete
- (BPStubRequest *) parseRequest:(NSData *)buf
{
    NSData *sep = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    NSRange r = [buf rangeOfData:sep options:0 range:NSMakeRange(0, buf.length)];
    if (r.location == NSNotFound) return nil;
    NSString *head = [[NSString alloc] initWithData:[buf subdataWithRange:NSMakeRange(0, r.location)]
                                           encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *lines = [head componentsSeparatedByString:@"\r\n"];
    NSUInteger contentLength = 0;
    for (NSString *l in lines) {
        if ([[l lowercaseString] hasPrefix:@"content-length:"]) {
            contentLength = (NSUInteger)[[l substringFromIndex:15] integerValue];
        }
    }
    NSUInteger bodyStart = NSMaxRange(r);
    if (buf.length < bodyStart + contentLength) return nil;

    NSArray<NSString *> *requestLine = [lines.firstObject componentsSeparatedByString:@" "];
    if (requestLine.count < 2) return nil;
    NSURLComponents *c = [NSURLComponents componentsWithString:[@"http://stub" stringByAppendingString:requestLine[1]]];
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *it in c.queryItems) q[it.name] = it.value ?: @"";

    BPStubRequest *req = [BPStubRequest new];
    req.method = requestLine[0];
    req.path = c.path ?: @"/";
    req.query = q;
    req.body = [[NSString alloc] initWithData:[buf subdataWithRange:NSMakeRange(bodyStart, contentLength)]
                                     encoding:NSUTF8StringEncoding] ?: @"";
    return req;
}

// Records the request and computes the response (status, content type, body); used by both transports.
- (NSInteger) handle:(BPStubRequest *)req contentType:(NSString **)ctypeOut body:(NSData **)bodyOut
{
    @synchronized (_requests) {
        [_requests addObject:req];
    }
    NSInteger status = 200;
    NSString *ctype = @"text/plain";
    NSString *body = @"";

    if (self.failCount > 0) {
        self.failCount = self.failCount - 1;
        status = self.failStatus;
        body = @"stub failure";
    } else if ([req.path isEqualToString:@"/brouter"]) {
        NSString *lonlats = req.query[@"lonlats"] ?: @"";
        if ([lonlats componentsSeparatedByString:@"|"].count < 2) {
            status = 400;
            body = @"lonlats must contain at least 2 points";
        } else {
            if ([req.query[@"format"] isEqualToString:@"geojson"]) {   // used by the app since #53
                ctype = @"application/vnd.geo+json";
                body = [[self class] geojsonForLonLats:lonlats];
            } else {
                ctype = @"application/gpx+xml";
                body = [[self class] gpxForLonLats:lonlats];
            }
        }
    } else if ([req.path hasPrefix:@"/brouter/profiles2/"]) {
        // annotated like the brouter.de profiles: "# %name% | description | type" (#39)
        body = @"# *** stub profile\n"
               @"---context:global\n"
               @"assign validForBikes = true\n"
               @"# Elevation\n"
               @"assign   downhillcost     = 60     # %downhillcost% | Cost for going downhill | number\n"
               @"assign   uphillcutoff     = 1.5    # %uphillcutoff% | Gradients below this value in percents are not counted. | number\n"
               @"assign   avoid_unsafe     = false  # %avoid_unsafe% | Set true to avoid standard highways | boolean\n"
               @"# Kinematic model\n"
               @"assign   totalMass        = 90     # %totalMass% | Mass (in kg) of the bike + biker | number\n"
               @"assign   mode             = 1      # %mode% | Mode | [0=none, 1=auto, 2=other]\n"
               @"assign   turnInstructionMode = 1   # %turnInstructionMode% | Mode for the generated turn instructions | [0=none, 1=auto-choose]\n"
               @"assign   downhillcost     = if avoid_unsafe then 0 else downhillcost\n"
               @"---context:way\n"
               @"assign   classifier_none  = 1      # %classifier_none% | internal | number\n";
    } else if ([req.path isEqualToString:@"/api/interpreter"]) {
        ctype = @"application/json";
        body = [self overpassJSONForQuery:req.body];
    } else {
        status = 404;
        body = @"not found";
    }

    *ctypeOut = ctype;
    *bodyOut = [body dataUsingEncoding:NSUTF8StringEncoding];
    return status;
}

- (void) respondTo:(BPStubRequest *)req on:(nw_connection_t)conn
{
    NSString *ctype = nil;
    NSData *payload = nil;
    NSInteger status = [self handle:req contentType:&ctype body:&payload];
    NSString *header = [NSString stringWithFormat:
                        @"HTTP/1.1 %ld Stub\r\nContent-Type: %@\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",
                        (long)status, ctype, (unsigned long)payload.length];
    NSMutableData *out = [[header dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [out appendData:payload];
    NSData *outCopy = [out copy];
    dispatch_data_t data = dispatch_data_create(outCopy.bytes, outCopy.length, _queue, ^{ (void)outCopy; });

    void (^send)(void) = ^{
        nw_connection_send(conn, data, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t error) {
            nw_connection_cancel(conn);
        });
    };
    if (self.responseDelay > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.responseDelay * NSEC_PER_SEC)), _queue, send);
    } else {
        send();
    }
}

#pragma mark - fake services

static double BPDistance(double lat1, double lon1, double lat2, double lon2)
{
    double r = 6371000.0, p = M_PI / 180.0;
    double dlat = (lat2 - lat1) * p, dlon = (lon2 - lon1) * p;
    double a = sin(dlat / 2) * sin(dlat / 2) + cos(lat1 * p) * cos(lat2 * p) * sin(dlon / 2) * sin(dlon / 2);
    return 2 * r * asin(sqrt(a));
}

+ (NSString *) gpxForLonLats:(NSString *)lonlats
{
    NSMutableArray<NSArray<NSNumber *> *> *wps = [NSMutableArray array];
    for (NSString *p in [lonlats componentsSeparatedByString:@"|"]) {
        NSArray *c = [p componentsSeparatedByString:@","];
        if (c.count == 2) [wps addObject:@[@([c[1] doubleValue]), @([c[0] doubleValue])]]; // lat, lon
    }
    const int steps = 10;
    NSMutableString *pts = [NSMutableString string];
    double len = 0, ascend = 0, prevLat = 0, prevLon = 0, prevEle = 0;
    int n = 0;
    for (NSUInteger i = 0; i + 1 < wps.count; i++) {
        for (int k = (i == 0 ? 0 : 1); k <= steps; k++) {
            double t = (double)k / steps;
            double lat = wps[i][0].doubleValue + t * (wps[i + 1][0].doubleValue - wps[i][0].doubleValue);
            double lon = wps[i][1].doubleValue + t * (wps[i + 1][1].doubleValue - wps[i][1].doubleValue);
            double ele = 100.0 + 50.0 * sin(n / 5.0);
            if (n > 0) {
                len += BPDistance(prevLat, prevLon, lat, lon);
                if (ele > prevEle) ascend += ele - prevEle;
            }
            [pts appendFormat:@"   <trkpt lon=\"%.6f\" lat=\"%.6f\"><ele>%.2f</ele></trkpt>\n", lon, lat, ele];
            prevLat = lat; prevLon = lon; prevEle = ele;
            n++;
        }
    }
    return [NSString stringWithFormat:
            @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            @"<!-- track-length = %.0f filtered ascend = %.0f plain-ascend = 0 cost=%.0f energy=.1kwh time=10m 0s -->\n"
            @"<gpx xmlns=\"http://www.topografix.com/GPX/1/1\" creator=\"BPStubServer\" version=\"1.1\">\n"
            @" <trk>\n  <name>brouter_stub_0</name>\n  <trkseg>\n%@  </trkseg>\n </trk>\n</gpx>\n",
            len, ascend, len, pts];
}

// same points as gpxForLonLats:, as BRouter GeoJSON; way tags: first half tertiary/asphalt, second half track/gravel
+ (NSString *) geojsonForLonLats:(NSString *)lonlats
{
    NSMutableArray<NSArray<NSNumber *> *> *wps = [NSMutableArray array];
    for (NSString *p in [lonlats componentsSeparatedByString:@"|"]) {
        NSArray *c = [p componentsSeparatedByString:@","];
        if (c.count == 2) [wps addObject:@[@([c[1] doubleValue]), @([c[0] doubleValue])]]; // lat, lon
    }
    const int steps = 10;
    NSMutableArray<NSArray<NSNumber *> *> *pts = [NSMutableArray array]; // lon, lat, ele
    int n = 0;
    for (NSUInteger i = 0; i + 1 < wps.count; i++) {
        for (int k = (i == 0 ? 0 : 1); k <= steps; k++) {
            double t = (double)k / steps;
            double lat = wps[i][0].doubleValue + t * (wps[i + 1][0].doubleValue - wps[i][0].doubleValue);
            double lon = wps[i][1].doubleValue + t * (wps[i + 1][1].doubleValue - wps[i][1].doubleValue);
            [pts addObject:@[@(lon), @(lat), @(100.0 + 50.0 * sin(n / 5.0))]];
            n++;
        }
    }
    NSMutableArray *messages = [NSMutableArray arrayWithObject:@[@"Longitude", @"Latitude", @"Elevation", @"Distance",
        @"CostPerKm", @"ElevCost", @"TurnCost", @"NodeCost", @"InitialCost", @"WayTags", @"NodeTags", @"Time", @"Energy"]];
    long len = 0;
    double ascend = 0;
    for (NSUInteger i = 1; i < pts.count; i++) {
        long d = lround(BPDistance(pts[i - 1][1].doubleValue, pts[i - 1][0].doubleValue, pts[i][1].doubleValue, pts[i][0].doubleValue));
        len += d;
        if (pts[i][2].doubleValue > pts[i - 1][2].doubleValue) ascend += pts[i][2].doubleValue - pts[i - 1][2].doubleValue;
        NSString *tags = (i <= pts.count / 2) ? @"highway=tertiary surface=asphalt" : @"highway=track surface=gravel";
        [messages addObject:@[ [NSString stringWithFormat:@"%ld", lround(pts[i][0].doubleValue * 1e6)],
                               [NSString stringWithFormat:@"%ld", lround(pts[i][1].doubleValue * 1e6)],
                               [NSString stringWithFormat:@"%.0f", pts[i][2].doubleValue],
                               [NSString stringWithFormat:@"%ld", d], @"1000", @"0", @"0", @"0", @"0", tags, @"", @"0", @"0" ]];
    }
    NSDictionary *geo = @{ @"type": @"FeatureCollection", @"features": @[ @{
        @"type": @"Feature",
        @"properties": @{ @"creator": @"BPStubServer", @"name": @"brouter_stub_0",
                          @"track-length": [NSString stringWithFormat:@"%ld", len],
                          @"filtered ascend": [NSString stringWithFormat:@"%.0f", ascend],
                          @"plain-ascend": @"0", @"total-time": @"600", @"total-energy": @"360000",
                          @"cost": [NSString stringWithFormat:@"%ld", len], @"messages": messages },
        @"geometry": @{ @"type": @"LineString", @"coordinates": pts } } ] };
    return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:geo options:0 error:NULL]
                                 encoding:NSUTF8StringEncoding];
}

- (NSString *) overpassJSONForQuery:(NSString *)q
{
    // POIs placed ~1 km from the first sampled route point (N: water, E: toilets, S: cemetery)
    double lat = 44.0, lon = 0.5;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"around:\\d+,([-\\d.]+),([-\\d.]+)"
                                                                        options:0 error:NULL];
    NSTextCheckingResult *m = [re firstMatchInString:q options:0 range:NSMakeRange(0, q.length)];
    if (m) {
        lat = [[q substringWithRange:[m rangeAtIndex:1]] doubleValue];
        lon = [[q substringWithRange:[m rangeAtIndex:2]] doubleValue];
    }
    NSDictionary *json = @{
        @"elements": @[
            @{ @"type": @"node", @"id": @1001, @"lat": @(lat + 0.01), @"lon": @(lon),
               @"tags": @{ @"amenity": @"drinking_water" } },
            @{ @"type": @"node", @"id": @1002, @"lat": @(lat), @"lon": @(lon + 0.01),
               @"tags": @{ @"amenity": @"toilets" } },
            @{ @"type": @"way", @"id": @1003, @"center": @{ @"lat": @(lat - 0.01), @"lon": @(lon) },
               @"tags": @{ @"landuse": @"cemetery" } },
        ]
    };
    NSData *d = [NSJSONSerialization dataWithJSONObject:json options:0 error:NULL];
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

@end
