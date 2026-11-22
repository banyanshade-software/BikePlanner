//
//  RAGarminConnectTests.m
//  RideAnalyzerTests
//
//  Fetching the rides from Garmin Connect (#82, R1), against a stub of the Personal API (never the real service):
//  token exchange, list, ZIP download, 401 retry, incremental and bulk fetches, cancellation. And the ZIP reader.
//

#import <XCTest/XCTest.h>
#import "RAGarminConnect.h"
#import "RAZipReader.h"
#import "RALibraryDocument.h"
#import "RARide.h"
#import "RAEquipment.h"
#import "RATestSupport.h"

static NSString *const kBase = @"https://garmin.stub";

@interface RAGarminConnectTests : XCTestCase
@end

@implementation RAGarminConnectTests
{
    NSMutableArray<NSDictionary *> *_activities;   // newest first, as Garmin lists them
    NSMutableDictionary<NSString *, NSData *> *_fits;
    NSMutableDictionary<NSString *, NSData *> *_gpxs;   // GPX exports (they follow the cuts made in Garmin Connect)
    NSMutableDictionary<NSString *, NSData *> *_tcxs;   // TCX exports (the same)
    NSInteger _tokenCount;
    BOOL _rejectKey;
    BOOL _expireNextAPICall;
    NSInteger _busyAnswers;      // the next requests answered with HTTP 408
    id _weightRange;             // answers of the weight endpoints (nil: 404)
    id _weightDateRange;
    id _userSettings;
}

- (void)setUp
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:[kBase stringByAppendingString:@"/token"] forKey:@"RAGarminTokenURL"];
    [ud setObject:kBase forKey:@"RAGarminAPIBaseURL"];
    [RAStubURLProtocol reset];
    _activities = [NSMutableArray array];
    _fits = [NSMutableDictionary dictionary];
    _gpxs = [NSMutableDictionary dictionary];
    _tcxs = [NSMutableDictionary dictionary];
    _tokenCount = 0;
    _rejectKey = NO;
    _expireNextAPICall = NO;
    _busyAnswers = 0;
    _weightRange = nil;
    _weightDateRange = nil;
    _userSettings = nil;
    __weak RAGarminConnectTests *weakSelf = self;
    RAStubURLProtocol.handler = ^RAStubResponse *(NSURLRequest *r) { return [weakSelf answer:r]; };
}

- (void)tearDown
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud removeObjectForKey:@"RAGarminTokenURL"];
    [ud removeObjectForKey:@"RAGarminAPIBaseURL"];
    [RAStubURLProtocol reset];
}

// the Personal API, as far as the app uses it
- (nullable RAStubResponse *)answer:(NSURLRequest *)r
{
    NSString *path = r.URL.path;
    NSString *auth = [r valueForHTTPHeaderField:@"Authorization"] ?: @"";
    if (_busyAnswers > 0) {
        _busyAnswers--;
        return [RAStubResponse status:408 body:[@"Request Timeout" dataUsingEncoding:NSUTF8StringEncoding]];
    }
    if ([path isEqualToString:@"/token"]) {
        if ([[r valueForHTTPHeaderField:@"Accept"] isEqualToString:@"application/json"]) {
            return [RAStubResponse status:406 body:nil]; // as Garmin did
        }
        if (![r.HTTPMethod isEqualToString:@"POST"] || ![auth isEqualToString:@"ApiKey good-key"] || _rejectKey) {
            return [RAStubResponse status:401 body:nil];
        }
        _tokenCount++;
        NSString *token = RAJWT([NSDate dateWithTimeIntervalSinceNow:3600]);
        return [RAStubResponse json:@{ @"access_token": [token stringByAppendingFormat:@"%ld", (long)_tokenCount] }];
    }
    if (![auth hasPrefix:@"Bearer "]) return [RAStubResponse status:401 body:nil];
    if (_expireNextAPICall) {
        _expireNextAPICall = NO;
        return [RAStubResponse status:401 body:nil];
    }
    if ([path isEqualToString:@"/activitylist-service/activities/search/activities"]) {
        NSURLComponents *c = [NSURLComponents componentsWithURL:r.URL resolvingAgainstBaseURL:NO];
        NSUInteger start = 0, limit = 20;
        for (NSURLQueryItem *q in c.queryItems) {
            if ([q.name isEqualToString:@"start"]) start = (NSUInteger)q.value.integerValue;
            if ([q.name isEqualToString:@"limit"]) limit = (NSUInteger)q.value.integerValue;
        }
        NSArray *page = start < _activities.count
            ? [_activities subarrayWithRange:NSMakeRange(start, MIN(limit, _activities.count - start))] : @[];
        return [RAStubResponse json:page];
    }
    if ([path hasPrefix:@"/weight-service/weight/range/"]) return _weightRange ? [RAStubResponse json:_weightRange] : nil;
    if ([path isEqualToString:@"/weight-service/weight/dateRange"]) return _weightDateRange ? [RAStubResponse json:_weightDateRange] : nil;
    if ([path isEqualToString:@"/userprofile-service/userprofile/user-settings"]) return _userSettings ? [RAStubResponse json:_userSettings] : nil;
    NSString *gpxPrefix = @"/download-service/export/gpx/activity/";
    if ([path hasPrefix:gpxPrefix]) {
        NSData *gpx = _gpxs[[path substringFromIndex:gpxPrefix.length]];
        return gpx ? [RAStubResponse status:200 body:gpx] : [RAStubResponse status:404 body:nil];
    }
    NSString *tcxPrefix = @"/download-service/export/tcx/activity/";
    if ([path hasPrefix:tcxPrefix]) {
        NSData *tcx = _tcxs[[path substringFromIndex:tcxPrefix.length]];
        return tcx ? [RAStubResponse status:200 body:tcx] : [RAStubResponse status:404 body:nil];
    }
    NSString *prefix = @"/download-service/files/activity/";
    if ([path hasPrefix:prefix]) {
        NSString *identifier = [path substringFromIndex:prefix.length];
        NSData *fit = _fits[identifier];
        if (!fit) return [RAStubResponse status:404 body:nil];
        return [RAStubResponse status:200 body:RAZip([identifier stringByAppendingString:@"_ACTIVITY.fit"], fit, YES)];
    }
    return nil;
}

// an activity of Garmin Connect, day `day` (newest first: insert at the front)
- (void)addActivity:(NSInteger)identifier day:(NSInteger)day type:(NSString *)type
{
    NSArray<NSNumber *> *alts = @[ @100, @(120 + day), @130 ];
    CLLocation *start = RATrace(alts, day * 86400).firstObject;
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    f.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    [_activities insertObject:@{ @"activityId": @(identifier), @"activityName": [NSString stringWithFormat:@"Ride %ld", (long)identifier],
                                  @"startTimeGMT": [f stringFromDate:start.timestamp], @"distance": @2224,
                                  @"activityType": @{ @"typeKey": type } } atIndex:0];
    _fits[[NSString stringWithFormat:@"%ld", (long)identifier]] = RAFIT(alts, day * 86400, 3122, 99);
}

- (RAGarminConnect *)clientWithKey:(NSString *)key
{
    RAGarminConnect *client = [[RAGarminConnect alloc] initWithKey:key session:[RAStubURLProtocol session]];
    client.retryDelay = 0;
    return client;
}

- (RAImportSummary *)fetchInto:(RALibraryDocument *)doc client:(RAGarminConnect *)client since:(nullable NSDate *)since
                         error:(NSError **)outError
{
    __block BOOL done = NO;
    __block RAImportSummary *result = nil;
    __block NSError *error = nil;
    NSProgress *progress = [doc fetchFromGarmin:client since:since completion:^(RAImportSummary *s, NSError *e) {
        result = s;
        error = e;
        done = YES;
    }];
    XCTAssertNotNil(progress);
    XCTAssertTrue(RAWaitUntil(10, ^{ return done; }));
    if (outError) *outError = error;
    return result;
}

#pragma mark - ZIP

- (void)testZipReader
{
    NSData *content = [[@"" stringByPaddingToLength:5000 withString:@"FIT data " startingAtIndex:0]
                       dataUsingEncoding:NSUTF8StringEncoding];
    for (NSNumber *deflate in @[ @NO, @YES ]) {
        NSData *zip = RAZip(@"123_ACTIVITY.fit", content, deflate.boolValue);
        XCTAssertTrue([RAZipReader isZipData:zip]);
        NSError *error = nil;
        NSDictionary<NSString *, NSData *> *entries = [RAZipReader entriesOfZipData:zip error:&error];
        XCTAssertNotNil(entries, @"%@", error);
        XCTAssertEqualObjects(entries[@"123_ACTIVITY.fit"], content);
        if (deflate.boolValue) XCTAssertLessThan(zip.length, content.length, @"really deflated");
    }
    NSData *zip = RAZip(@"a.fit", content, YES);
    NSData *truncated = [zip subdataWithRange:NSMakeRange(0, zip.length / 2)];
    NSError *error = nil;
    XCTAssertNil([RAZipReader entriesOfZipData:truncated error:&error]);
    XCTAssertNotNil(error);
    XCTAssertNil([RAZipReader entriesOfZipData:content error:NULL], @"not a ZIP");
    XCTAssertFalse([RAZipReader isZipData:content]);
}

#pragma mark - client

- (void)testJWTExpiry
{
    NSDate *exp = [NSDate dateWithTimeIntervalSince1970:1795500000];
    XCTAssertEqualObjects([RAGarminConnect expiryOfJWT:RAJWT(exp)], exp);
    XCTAssertNil([RAGarminConnect expiryOfJWT:@"not-a-jwt"]);
}

- (void)testActivityJSON
{
    RAGarminActivity *a = [RAGarminActivity activityWithJSON:@{ @"activityId": @123, @"activityName": @"Col",
        @"startTimeGMT": @"2026-11-18 08:00:00", @"distance": @42000.5, @"activityType": @{ @"typeKey": @"road_biking" } }];
    XCTAssertEqualObjects(a.activityID, @"123");
    XCTAssertEqualObjects(a.name, @"Col");
    XCTAssertEqualObjects(a.startDate, [NSDate dateWithTimeIntervalSince1970:1795478400 + 8 * 3600]);
    XCTAssertEqualWithAccuracy(a.distance, 42000.5, 1e-9);
    XCTAssertTrue(a.isOutdoorCycling);
    for (NSString *t in @[ @"cycling", @"gravel_cycling", @"mountain_biking", @"e_bike_mountain" ]) {
        a.typeKey = t;
        XCTAssertTrue(a.isOutdoorCycling, @"%@", t);
    }
    for (NSString *t in @[ @"indoor_cycling", @"virtual_ride", @"running", @"" ]) {
        a.typeKey = t;
        XCTAssertFalse(a.isOutdoorCycling, @"%@", t);
    }
    XCTAssertNil([RAGarminActivity activityWithJSON:@{ @"activityName": @"no id" }]);
}

- (void)testTokenListAndDownload
{
    [self addActivity:11 day:0 type:@"road_biking"];
    RAGarminConnect *client = [self clientWithKey:@"good-key"];
    __block NSArray<RAGarminActivity *> *list = nil;
    [client activitiesFrom:0 limit:50 startDate:nil completion:^(NSArray<RAGarminActivity *> *a, NSError *e) { list = a; }];
    XCTAssertTrue(RAWaitUntil(5, ^{ return (BOOL)(list != nil); }));
    XCTAssertEqual(list.count, 1u);
    XCTAssertEqual(_tokenCount, 1);
    NSURLRequest *listRequest = RAStubURLProtocol.requests.lastObject;
    XCTAssertTrue([[listRequest valueForHTTPHeaderField:@"Authorization"] hasPrefix:@"Bearer "]);
    XCTAssertTrue([[listRequest valueForHTTPHeaderField:@"User-Agent"] hasPrefix:@"RideAnalyzer/"]);
    XCTAssertTrue([listRequest.URL.query containsString:@"start=0"]);
    XCTAssertTrue([listRequest.URL.query containsString:@"limit=50"]);

    __block NSData *fit = nil;
    [client fitFileOfActivity:@"11" completion:^(NSData *f, NSError *e) { fit = f; }];
    XCTAssertTrue(RAWaitUntil(5, ^{ return (BOOL)(fit != nil); }));
    XCTAssertEqualObjects(fit, _fits[@"11"], @"the FIT file out of the ZIP");
    XCTAssertEqual(_tokenCount, 1, @"the token is reused while valid");

    // an expired token (401): a new one, and the request again
    _expireNextAPICall = YES;
    list = nil;
    [client activitiesFrom:0 limit:50 startDate:[NSDate dateWithTimeIntervalSince1970:1795478400]
                completion:^(NSArray<RAGarminActivity *> *a, NSError *e) { list = a; }];
    XCTAssertTrue(RAWaitUntil(5, ^{ return (BOOL)(list != nil); }));
    XCTAssertEqual(_tokenCount, 2);
    XCTAssertTrue([RAStubURLProtocol.requests.lastObject.URL.query containsString:@"startDate=2026-11-18"]);
}

// the owner's first try (2026-11-21) got HTTP 406 on the token: the token request accepts any type (and has an empty
// body with its length); a timeout (408) gets one retry, a second one is an error that says which request failed
- (void)testTimeouts
{
    [self addActivity:11 day:0 type:@"road_biking"];
    RAGarminConnect *client = [self clientWithKey:@"good-key"];
    _busyAnswers = 1;
    __block NSArray<RAGarminActivity *> *list = nil;
    [client activitiesFrom:0 limit:50 startDate:nil completion:^(NSArray<RAGarminActivity *> *a, NSError *e) { list = a; }];
    XCTAssertTrue(RAWaitUntil(5, ^{ return (BOOL)(list != nil); }), @"retried after the 408");
    NSURLRequest *token = [RAStubURLProtocol.requests filteredArrayUsingPredicate:
                           [NSPredicate predicateWithFormat:@"URL.path == '/token'"]].lastObject;
    XCTAssertEqualObjects([token valueForHTTPHeaderField:@"Content-Length"], @"0");
    XCTAssertTrue([[token valueForHTTPHeaderField:@"Accept"] containsString:@"*/*"], @"not JSON only (HTTP 406)");

    RAGarminConnect *other = [self clientWithKey:@"good-key"];
    _busyAnswers = 2;
    __block NSError *error = nil;
    [other activitiesFrom:0 limit:50 startDate:nil completion:^(NSArray<RAGarminActivity *> *a, NSError *e) { error = e; }];
    XCTAssertTrue(RAWaitUntil(5, ^{ return (BOOL)(error != nil); }));
    XCTAssertEqual(error.code, RAGarminErrorHTTP);
    XCTAssertEqualObjects(error.userInfo[RAGarminHTTPStatusKey], @408);
    XCTAssertEqualObjects(error.userInfo[RAGarminStepKey], @"token");
    XCTAssertTrue([error.localizedRecoverySuggestion containsString:@"Request Timeout"], @"%@", error.localizedRecoverySuggestion);
}

- (void)testRejectedKey
{
    RAGarminConnect *client = [self clientWithKey:@"bad-key"];
    __block NSError *error = nil;
    [client activitiesFrom:0 limit:50 startDate:nil completion:^(NSArray<RAGarminActivity *> *a, NSError *e) { error = e; }];
    XCTAssertTrue(RAWaitUntil(5, ^{ return (BOOL)(error != nil); }));
    XCTAssertEqualObjects(error.domain, RAGarminErrorDomain);
    XCTAssertEqual(error.code, RAGarminErrorKeyRejected);
}

#pragma mark - fetching into a library

- (void)testIncrementalFetch
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    [self addActivity:1 day:0 type:@"road_biking"];
    [self addActivity:2 day:1 type:@"running"];
    [self addActivity:3 day:2 type:@"indoor_cycling"];
    [self addActivity:4 day:3 type:@"gravel_cycling"];
    NSError *error = nil;
    RAImportSummary *s = [self fetchInto:doc client:[self clientWithKey:@"good-key"] since:nil error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(s.imported, 2u, @"outdoor cycling only");
    XCTAssertEqual(doc.rides.count, 2u);
    XCTAssertNotNil(doc.garminLastFetch);
    RARide *ride = [doc.rides filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"garminActivityID == '4'"]].firstObject;
    XCTAssertEqualObjects(ride.name, @"Ride 4", @"named as in Garmin Connect");
    XCTAssertEqualObjects(ride.format, @"fit");
    XCTAssertEqualObjects(ride.deviceKey, @"p3122-s99");
    XCTAssertNotNil([doc originalDataOfRide:ride]);

    // new activities: the listing stops at the first one already in the library
    [self addActivity:5 day:4 type:@"cycling"];
    NSUInteger before = RAStubURLProtocol.requests.count;
    s = [self fetchInto:doc client:[self clientWithKey:@"good-key"] since:nil error:&error];
    XCTAssertEqual(s.imported, 1u);
    XCTAssertEqual(doc.rides.count, 3u);
    NSArray<NSURLRequest *> *requests = [RAStubURLProtocol.requests subarrayWithRange:
        NSMakeRange(before, RAStubURLProtocol.requests.count - before)];
    NSArray *downloads = [requests filteredArrayUsingPredicate:
        [NSPredicate predicateWithFormat:@"URL.path BEGINSWITH '/download-service'"]];
    XCTAssertEqual(downloads.count, 1u, @"only the new activity is downloaded");
}

- (void)testBulkFetchSinceADate
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    for (NSInteger i = 0; i < 120; i++) [self addActivity:100 + i day:i type:@"road_biking"]; // 3 pages of 50
    // already imported from a file: the Garmin activity is linked to it, not imported twice
    [doc importData:RAFIT(@[ @100, @(120 + 110), @130 ], 110 * 86400, 3122, 99) fileName:@"local.fit" error:NULL];
    NSDate *since = [NSDate dateWithTimeIntervalSince1970:1795478400 + 100 * 86400]; // day 100
    NSError *error = nil;
    RAImportSummary *s = [self fetchInto:doc client:[self clientWithKey:@"good-key"] since:since error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(s.imported, 19u, @"days 100 to 119, but day 110 was there");
    XCTAssertEqual(s.duplicates, 1u);
    XCTAssertEqual(doc.rides.count, 20u);
    RARide *local = [doc.rides filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"fileName == 'local.fit'"]].firstObject;
    XCTAssertEqualObjects(local.garminActivityID, @"210", @"linked to its Garmin activity");
    NSArray *lists = [RAStubURLProtocol.requests filteredArrayUsingPredicate:
        [NSPredicate predicateWithFormat:@"URL.path ENDSWITH 'activities'"]];
    XCTAssertEqual(lists.count, 1u, @"the first page reaches the start date (newest first)");
}

- (void)testFetchErrorsAndCancel
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    [self addActivity:1 day:0 type:@"road_biking"];
    NSError *error = nil;
    RAImportSummary *s = [self fetchInto:doc client:[self clientWithKey:@"bad-key"] since:nil error:&error];
    XCTAssertNil(s);
    XCTAssertEqual(error.code, RAGarminErrorKeyRejected);
    XCTAssertEqual(doc.rides.count, 0u);
    XCTAssertNil(doc.garminLastFetch);
    XCTAssertFalse(doc.importing);

    // a download that fails counts as unreadable, the others are imported
    [self addActivity:2 day:1 type:@"road_biking"];
    [_fits removeObjectForKey:@"2"];
    s = [self fetchInto:doc client:[self clientWithKey:@"good-key"] since:nil error:&error];
    XCTAssertEqual(s.imported, 1u);
    XCTAssertEqual(s.unreadable, 1u);

    // cancelled at once: nothing imported, the date of the last fetch unchanged
    RALibraryDocument *other = [[RALibraryDocument alloc] init];
    __block RAImportSummary *result = nil;
    NSProgress *progress = [other fetchFromGarmin:[self clientWithKey:@"good-key"] since:nil
                                       completion:^(RAImportSummary *summary, NSError *e) { result = summary; }];
    XCTAssertNil([other fetchFromGarmin:[self clientWithKey:@"good-key"] since:nil
                             completion:^(RAImportSummary *summary, NSError *e) {}], @"one at a time");
    [progress cancel];
    XCTAssertTrue(RAWaitUntil(10, ^{ return (BOOL)(result != nil); }));
    XCTAssertTrue(result.cancelled);
    XCTAssertNil(other.garminLastFetch);
}

- (void)testMemoryKeyStore
{
    id<RAKeyStore> store = [[RAMemoryKeyStore alloc] init];
    XCTAssertNil([store keyForLibrary:@"lib"]);
    [store setKey:@"k" forLibrary:@"lib"];
    XCTAssertEqualObjects([store keyForLibrary:@"lib"], @"k");
    XCTAssertNil([store keyForLibrary:@"other"], @"one key per library");
    [store setKey:nil forLibrary:@"lib"];
    XCTAssertNil([store keyForLibrary:@"lib"]);
}

// an activity cut in Garmin Connect (the computer left running): the file has the whole recording, the summary
// the corrected ride (owner's case: 277 km of which 3 by bike)
- (void)testActivityCutInGarminConnect
{
    [self addActivity:31 day:0 type:@"road_biking"];
    NSMutableDictionary *cut = [_activities[0] mutableCopy];
    cut[@"distance"] = @1112;
    cut[@"elapsedDuration"] = @600;
    _activities[0] = cut;
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    NSError *error = nil;
    [self fetchInto:doc client:[self clientWithKey:@"good-key"] since:nil error:&error];
    RARide *ride = doc.rides.firstObject;
    XCTAssertNotNil(ride, @"%@", error);
    XCTAssertTrue(ride.trimmed);
    XCTAssertEqualWithAccuracy(ride.distance, 1112, 30, @"the part kept in Garmin Connect");
    XCTAssertEqualWithAccuracy(ride.trimEnd, 600, 1e-6);
}

// a ride imported before it was cut in Garmin Connect: Apply Garmin Connect Corrections
- (void)testApplyGarminCorrections
{
    [self addActivity:32 day:0 type:@"road_biking"];
    [self addActivity:33 day:1 type:@"road_biking"];
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    doc.undoManager.groupsByEvent = NO;
    NSError *error = nil;
    [doc.undoManager beginUndoGrouping];
    [self fetchInto:doc client:[self clientWithKey:@"good-key"] since:nil error:&error];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqual(doc.rides.count, 2u);
    for (RARide *r in doc.rides) XCTAssertFalse(r.trimmed, @"nothing cut yet");

    NSUInteger index = [_activities indexOfObjectPassingTest:^BOOL(NSDictionary *a, NSUInteger i, BOOL *stop) {
        return [a[@"activityId"] isEqual:@32];
    }];
    NSMutableDictionary *cut = [_activities[index] mutableCopy];
    cut[@"distance"] = @1112;
    cut[@"elapsedDuration"] = @600;
    _activities[index] = cut;

    __block NSUInteger corrected = 99;
    __block BOOL done = NO;
    XCTAssertNotNil([doc applyGarminCorrections:[self clientWithKey:@"good-key"] completion:^(NSUInteger n, NSError *e) {
        corrected = n;
        done = YES;
    }]);
    XCTAssertTrue(RAWaitUntil(10, ^{ return done; }));
    XCTAssertEqual(corrected, 1u);
    RARide *r32 = [doc.rides filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"garminActivityID == '32'"]].firstObject;
    RARide *r33 = [doc.rides filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"garminActivityID == '33'"]].firstObject;
    XCTAssertTrue(r32.trimmed);
    XCTAssertEqualWithAccuracy(r32.distance, 1112, 30);
    XCTAssertFalse(r33.trimmed);
    [doc.undoManager undo];
    XCTAssertFalse(r32.trimmed, @"undoable");
    XCTAssertEqualWithAccuracy(r32.distance, 2224, 30);
}

// the GPX export follows the cut (owner's June 6 activity: the FIT has 276.7 km, the GPX the 6:55 kept), even
// when the summary has no duration
- (void)testCutFromTheGPXExport
{
    [self addActivity:34 day:0 type:@"road_biking"];
    NSMutableDictionary *cut = [_activities[0] mutableCopy];
    cut[@"distance"] = @1112;                                 // no duration in this summary
    _activities[0] = cut;
    // the export: the last two points only (the start was cut)
    NSArray<CLLocation *> *trace = RATrace(@[ @100, @120, @130 ], 0);
    NSISO8601DateFormatter *f = [[NSISO8601DateFormatter alloc] init];
    NSMutableString *gpx = [NSMutableString stringWithString:@"<?xml version=\"1.0\"?><gpx version=\"1.1\" creator=\"Garmin Connect\"><trk><trkseg>"];
    for (NSUInteger i = 1; i < trace.count; i++) {
        [gpx appendFormat:@"<trkpt lat=\"%.7f\" lon=\"%.7f\"><ele>%.0f</ele><time>%@</time></trkpt>",
         trace[i].coordinate.latitude, trace[i].coordinate.longitude, trace[i].altitude, [f stringFromDate:trace[i].timestamp]];
    }
    [gpx appendString:@"</trkseg></trk></gpx>"];
    _gpxs[@"34"] = [gpx dataUsingEncoding:NSUTF8StringEncoding];

    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    NSError *error = nil;
    [self fetchInto:doc client:[self clientWithKey:@"good-key"] since:nil error:&error];
    RARide *ride = doc.rides.firstObject;
    XCTAssertNotNil(ride, @"%@", error);
    XCTAssertEqualWithAccuracy(ride.trimStart, 600, 1, @"from the first time of the export");
    XCTAssertEqual(ride.trimEnd, 0, @"the end is not cut");
    XCTAssertEqualWithAccuracy(ride.distance, 1112, 30);

    NSTimeInterval s = 0, e = 0;
    XCTAssertFalse([RALibraryDocument trimOfData:_fits[@"34"] matchingGPX:[@"<gpx/>" dataUsingEncoding:NSUTF8StringEncoding]
                                           start:&s end:&e], @"no times");
}

// no GPX export: the TCX export, which follows the cut too (checked with the owner's June 6 activity)
- (void)testCutFromTheTCXExport
{
    [self addActivity:35 day:0 type:@"road_biking"];
    NSMutableDictionary *cut = [_activities[0] mutableCopy];
    cut[@"distance"] = @1112;
    _activities[0] = cut;
    _tcxs[@"35"] = RATCX(@[ @100, @120 ], 0, @"vívomove Style", @3308);    // the first two points: the end was cut
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    NSError *error = nil;
    [self fetchInto:doc client:[self clientWithKey:@"good-key"] since:nil error:&error];
    RARide *ride = doc.rides.firstObject;
    XCTAssertNotNil(ride, @"%@", error);
    XCTAssertEqual(ride.trimStart, 0);
    XCTAssertEqualWithAccuracy(ride.trimEnd, 601, 1, @"to the last time of the export");
    XCTAssertEqualWithAccuracy(ride.distance, 1112, 30);
}

#pragma mark - weighings (R11)

- (void)testWeighingsOfTheThreeAnswers
{
    NSArray<RAWeighing *> *a = [RAGarminConnect weighingsOfJSON:@{ @"dailyWeightSummaries": @[
        @{ @"summaryDate": @"2026-11-02", @"latestWeight": @{ @"weight": @72400.0, @"date": @1793620800000, @"calendarDate": @"2026-11-02" } },
        @{ @"summaryDate": @"2026-11-01", @"allWeightMetrics": @[ @{ @"weight": @73100, @"calendarDate": @"2026-11-01" } ] } ] }];
    XCTAssertEqual(a.count, 2u);
    XCTAssertEqualWithAccuracy(a[0].kilograms, 73.1, 1e-9, @"oldest first, grams to kg");
    XCTAssertEqualWithAccuracy(a[1].kilograms, 72.4, 1e-9);
    NSArray<RAWeighing *> *b = [RAGarminConnect weighingsOfJSON:@{ @"dateWeightList": @[ @{ @"date": @1793620800000, @"weight": @72400 } ] }];
    XCTAssertEqual(b.count, 1u);
    XCTAssertEqualObjects(b[0].date, [NSDate dateWithTimeIntervalSince1970:1793620800]);
    NSArray<RAWeighing *> *c = [RAGarminConnect weighingsOfJSON:@{ @"userData": @{ @"weight": @71000.0 } }];
    XCTAssertEqualWithAccuracy(c.firstObject.kilograms, 71, 1e-9);
    XCTAssertNil([RAGarminConnect weighingsOfJSON:@{ @"other": @1 }]);
    XCTAssertEqual([RAGarminConnect weighingsOfJSON:@{ @"dateWeightList": @[] }].count, 0u, @"an answer without weighing");
}

// the rides of a fetch get the weight of their day; another endpoint when the first does not answer
- (void)testFetchGetsTheWeighings
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    [self addActivity:1 day:0 type:@"road_biking"];
    _weightDateRange = @{ @"dateWeightList": @[ @{ @"date": @1795478400000, @"weight": @80000 },     // 2026-11-18
                                                 @{ @"date": @1795737600000, @"weight": @78000 } ] }; // 2026-11-21
    NSError *error = nil;
    RAImportSummary *s = [self fetchInto:doc client:[self clientWithKey:@"good-key"] since:nil error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(s.weighings, 2u);
    XCTAssertEqual(doc.equipment.weighings.count, 2u);
    NSArray *paths = [RAStubURLProtocol.requests valueForKeyPath:@"URL.path"];
    XCTAssertTrue([[paths filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH '/weight-service/weight/range/'"]] count] >= 1,
                  @"the range endpoint first");
    XCTAssertEqualWithAccuracy([doc.equipment riderWeightAtDate:[NSDate dateWithTimeIntervalSince1970:1795478400 + 3600]], 80, 1e-9);
    XCTAssertEqualWithAccuracy([doc.equipment riderWeightAtDate:[NSDate dateWithTimeIntervalSince1970:1795737600 + 86400 * 3]], 78, 1e-9);

    // again: nothing new
    __block NSInteger added = -1;
    [doc updateWeighingsFromGarmin:[self clientWithKey:@"good-key"] completion:^(NSUInteger n, NSError *e) { added = (NSInteger)n; }];
    XCTAssertTrue(RAWaitUntil(5, ^{ return (BOOL)(added >= 0); }));
    XCTAssertEqual(added, 0);

    // no weight endpoint answers: the fetch still succeeds
    _weightDateRange = nil;
    [self addActivity:2 day:1 type:@"road_biking"];
    s = [self fetchInto:doc client:[self clientWithKey:@"good-key"] since:nil error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(s.imported, 1u);
    XCTAssertEqual(s.weighings, 0u);
}

@end
