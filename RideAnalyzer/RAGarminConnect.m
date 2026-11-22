//
//  RAGarminConnect.m
//  RideAnalyzer
//

#import "RAGarminConnect.h"
#import "RAZipReader.h"
#import <Security/Security.h>

NSString *const RAGarminErrorDomain = @"RAGarminConnect";
NSString *const RAGarminHTTPStatusKey = @"RAGarminHTTPStatus";
NSString *const RAGarminStepKey = @"RAGarminStep";

static NSString *const RADefaultTokenURL =
    @"https://personal.connectapi.garmin.com/personalapitoken-service/personal-api/personal-api-key/token";
static NSString *const RADefaultAPIBaseURL = @"https://personal.connectapi.garmin.com";

@implementation RAEnvironment

+ (NSURL *)urlForDefault:(NSString *)key fallback:(NSString *)fallback
{
    NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    NSURL *url = s.length ? [NSURL URLWithString:s] : nil;
    return url ?: (NSURL *)[NSURL URLWithString:fallback];
}

+ (NSURL *)garminTokenURL
{
    return [self urlForDefault:@"RAGarminTokenURL" fallback:RADefaultTokenURL];
}

+ (NSURL *)garminAPIBaseURL
{
    return [self urlForDefault:@"RAGarminAPIBaseURL" fallback:RADefaultAPIBaseURL];
}

+ (NSString *)userAgent
{
    NSString *version = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"] ?: @"0";
    return [NSString stringWithFormat:@"RideAnalyzer/%@ (+https://github.com/banyanshade-software/BikePlanner)", version];
}

+ (NSMutableURLRequest *)requestWithURL:(NSURL *)url
{
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:url];
    [r setValue:[self userAgent] forHTTPHeaderField:@"User-Agent"];
    r.timeoutInterval = 60;
    return r;
}

@end

#pragma mark - key stores

@implementation RAKeychainKeyStore

+ (instancetype)shared
{
    static RAKeychainKeyStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [[RAKeychainKeyStore alloc] init]; });
    return store;
}

- (NSMutableDictionary *)queryForLibrary:(NSString *)libraryID
{
    return [@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"fr.free.daniel.braun.RideAnalyzer.GarminPersonalAPI",
        (__bridge id)kSecAttrAccount: libraryID,
    } mutableCopy];
}

- (nullable NSString *)keyForLibrary:(NSString *)libraryID
{
    NSMutableDictionary *q = [self queryForLibrary:libraryID];
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &result) != errSecSuccess) return nil;
    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (BOOL)setKey:(nullable NSString *)key forLibrary:(NSString *)libraryID
{
    SecItemDelete((__bridge CFDictionaryRef)[self queryForLibrary:libraryID]);
    if (key.length == 0) return YES;
    NSMutableDictionary *q = [self queryForLibrary:libraryID];
    q[(__bridge id)kSecAttrLabel] = @"Ride Analyzer – Garmin Connect Personal API";
    q[(__bridge id)kSecValueData] = [key dataUsingEncoding:NSUTF8StringEncoding];
    return SecItemAdd((__bridge CFDictionaryRef)q, NULL) == errSecSuccess;
}

@end

@implementation RAMemoryKeyStore
{
    NSMutableDictionary<NSString *, NSString *> *_keys;
}

- (instancetype)init
{
    self = [super init];
    if (self) _keys = [NSMutableDictionary dictionary];
    return self;
}

- (nullable NSString *)keyForLibrary:(NSString *)libraryID
{
    return _keys[libraryID];
}

- (BOOL)setKey:(nullable NSString *)key forLibrary:(NSString *)libraryID
{
    _keys[libraryID] = key.length ? key : nil;
    return YES;
}

@end

#pragma mark - activities

@implementation RAGarminActivity

+ (nullable instancetype)activityWithJSON:(NSDictionary *)json
{
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    id identifier = json[@"activityId"];
    if (![identifier isKindOfClass:[NSNumber class]] && ![identifier isKindOfClass:[NSString class]]) return nil;
    RAGarminActivity *a = [[RAGarminActivity alloc] init];
    a.activityID = [identifier description];
    id name = json[@"activityName"];
    a.name = [name isKindOfClass:[NSString class]] ? name : @"";
    id distance = json[@"distance"];
    a.distance = [distance isKindOfClass:[NSNumber class]] ? [distance doubleValue] : 0;
    id elapsed = json[@"elapsedDuration"] ?: json[@"duration"];
    a.elapsedDuration = [elapsed isKindOfClass:[NSNumber class]] ? MAX(0, [elapsed doubleValue]) : 0;
    id type = json[@"activityType"];
    id typeKey = [type isKindOfClass:[NSDictionary class]] ? type[@"typeKey"] : nil;
    a.typeKey = [typeKey isKindOfClass:[NSString class]] ? typeKey : @"";
    id start = json[@"startTimeGMT"];
    if ([start isKindOfClass:[NSString class]]) {
        static NSDateFormatter *f;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            f = [[NSDateFormatter alloc] init];
            f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            f.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            f.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        });
        a.startDate = [f dateFromString:start];
    }
    return a;
}

- (BOOL)isOutdoorCycling
{
    NSString *t = self.typeKey.lowercaseString;
    if ([t containsString:@"indoor"] || [t containsString:@"virtual"]) return NO;
    return [t containsString:@"cycling"] || [t containsString:@"biking"] || [t isEqualToString:@"bmx"];
}

@end

#pragma mark - client

@implementation RAGarminConnect
{
    NSString *_apiKey;
    NSURLSession *_session;
    NSString *_token;
    NSDate *_tokenExpiry;
}

- (instancetype)initWithKey:(NSString *)apiKey session:(NSURLSession *)session
{
    self = [super init];
    if (self) {
        _apiKey = [apiKey copy];
        _session = session;
        _retryDelay = 2;
    }
    return self;
}

- (nullable NSString *)token
{
    return _token;
}

+ (NSError *)errorWithCode:(RAGarminError)code status:(NSInteger)status
{
    return [self errorWithCode:code status:status step:nil body:nil];
}

// step: which request ("token", "list", "download"); body: the start of the answer, to understand an error (the
// answers of the token service never hold the key; the token itself is not shown)
+ (NSError *)errorWithCode:(RAGarminError)code status:(NSInteger)status step:(nullable NSString *)step
                      body:(nullable NSData *)body
{
    NSString *d = @"";
    switch (code) {
        case RAGarminErrorNoKey: d = NSLocalizedString(@"No Garmin Connect Personal API key.", @"Garmin"); break;
        case RAGarminErrorKeyRejected:
            d = NSLocalizedString(@"Garmin Connect rejected the Personal API key (wrong or expired).", @"Garmin"); break;
        case RAGarminErrorHTTP:
            d = [NSString stringWithFormat:NSLocalizedString(@"Garmin Connect answered with an error (HTTP %ld).", @"Garmin"),
                 (long)status]; break;
        case RAGarminErrorBadAnswer: d = NSLocalizedString(@"Unexpected answer from Garmin Connect.", @"Garmin"); break;
    }
    NSMutableDictionary *info = [@{ NSLocalizedDescriptionKey: d } mutableCopy];
    if (status) info[RAGarminHTTPStatusKey] = @(status);
    NSMutableArray<NSString *> *details = [NSMutableArray array];
    NSDictionary<NSString *, NSString *> *steps = @{
        @"token": NSLocalizedString(@"Step: exchanging the key for a token.", @"Garmin"),
        @"list": NSLocalizedString(@"Step: listing the activities.", @"Garmin"),
        @"download": NSLocalizedString(@"Step: downloading an activity.", @"Garmin"),
    };
    if (step && steps[step]) [details addObject:steps[step]];
    if (step) info[RAGarminStepKey] = step;
    NSString *text = body.length ? [[NSString alloc] initWithData:[body subdataWithRange:NSMakeRange(0, MIN(body.length, (NSUInteger)300))]
                                                         encoding:NSUTF8StringEncoding] : nil;
    text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length && ![step isEqualToString:@"token"]) [details addObject:text];
    else if (text.length && code != RAGarminErrorBadAnswer) [details addObject:text]; // an error page, not a token
    if (code == RAGarminErrorHTTP && (status == 408 || status == 429 || status >= 500)) {
        [details addObject:NSLocalizedString(@"Garmin Connect is busy or did not answer in time: try again later.", @"Garmin")];
    }
    if (details.count) info[NSLocalizedRecoverySuggestionErrorKey] = [details componentsJoinedByString:@"\n"];
    NSLog(@"RideAnalyzer: Garmin Connect %@: HTTP %ld", step ?: @"request", (long)status); // never the key or the token
    return [NSError errorWithDomain:RAGarminErrorDomain code:code userInfo:info];
}

/// an answer worth one more try: the server timed out, is overloaded or failing
+ (BOOL)isTransientStatus:(NSInteger)status
{
    return status == 408 || status == 429 || status == 502 || status == 503 || status == 504;
}

/// the delay before the retry: Retry-After when given (at most 30 s), else retryDelay
- (NSTimeInterval)retryDelayForResponse:(NSURLResponse *)response
{
    NSString *after = [response isKindOfClass:[NSHTTPURLResponse class]]
        ? [((NSHTTPURLResponse *)response) valueForHTTPHeaderField:@"Retry-After"] : nil;
    double seconds = after.doubleValue;
    return seconds > 0 ? MIN(seconds, 30) : self.retryDelay;
}

- (void)after:(NSTimeInterval)delay do:(dispatch_block_t)block
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

+ (nullable NSDate *)expiryOfJWT:(NSString *)token
{
    NSArray<NSString *> *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 3) return nil;
    NSString *payload = [[parts[1] stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
                         stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (payload.length % 4) payload = [payload stringByAppendingString:@"="];
    NSData *data = [[NSData alloc] initWithBase64EncodedString:payload options:0];
    NSDictionary *claims = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    id exp = [claims isKindOfClass:[NSDictionary class]] ? claims[@"exp"] : nil;
    return [exp isKindOfClass:[NSNumber class]] ? [NSDate dateWithTimeIntervalSince1970:[exp doubleValue]] : nil;
}

// the token answer: a JSON object with the token under one of the usual names, its expiry from expires_at /
// expires_in or from the JWT itself; a bare JWT is accepted too
- (BOOL)takeTokenFromData:(NSData *)data
{
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    NSString *token = nil;
    NSDate *expiry = nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        for (NSString *k in @[ @"access_token", @"accessToken", @"token" ]) {
            if ([json[k] isKindOfClass:[NSString class]]) { token = json[k]; break; }
        }
        id at = json[@"expires_at"] ?: json[@"expiresAt"];
        id inSeconds = json[@"expires_in"] ?: json[@"expiresIn"];
        if ([at isKindOfClass:[NSNumber class]]) expiry = [NSDate dateWithTimeIntervalSince1970:[at doubleValue]];
        else if ([inSeconds isKindOfClass:[NSNumber class]]) expiry = [NSDate dateWithTimeIntervalSinceNow:[inSeconds doubleValue]];
    } else {
        NSString *s = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                       stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([RAGarminConnect expiryOfJWT:s]) token = s;
    }
    if (token.length == 0) return NO;
    _token = token;
    _tokenExpiry = expiry ?: [RAGarminConnect expiryOfJWT:token] ?: [NSDate dateWithTimeIntervalSinceNow:23 * 3600];
    return YES;
}

// completion on the main queue
- (void)obtainTokenWithCompletion:(void (^)(NSError * _Nullable error))completion
{
    [self obtainTokenRetried:NO completion:completion];
}

- (void)obtainTokenRetried:(BOOL)retried completion:(void (^)(NSError * _Nullable error))completion
{
    if (_apiKey.length == 0) {
        completion([RAGarminConnect errorWithCode:RAGarminErrorNoKey status:0]);
        return;
    }
    NSMutableURLRequest *r = [RAEnvironment requestWithURL:[RAEnvironment garminTokenURL]];
    r.HTTPMethod = @"POST";
    // an empty body with its length: without, a server may wait for a body and time out (HTTP 408)
    r.HTTPBody = [NSData data];
    [r setValue:@"0" forHTTPHeaderField:@"Content-Length"];
    [r setValue:[@"ApiKey " stringByAppendingString:_apiKey] forHTTPHeaderField:@"Authorization"];
    // any type: with "Accept: application/json" only, Garmin answered HTTP 406 (the owner's first try, 2026-11-21);
    // the answer is read as JSON or as a bare token
    [r setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"Accept"];
    [[_session dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) { completion(error); return; }
            if ([RAGarminConnect isTransientStatus:status] && !retried) {
                [self after:[self retryDelayForResponse:response] do:^{ [self obtainTokenRetried:YES completion:completion]; }];
                return;
            }
            if (status == 401 || status == 403) {
                completion([RAGarminConnect errorWithCode:RAGarminErrorKeyRejected status:status step:@"token" body:data]);
                return;
            }
            if (status < 200 || status >= 300) {
                completion([RAGarminConnect errorWithCode:RAGarminErrorHTTP status:status step:@"token" body:data]);
                return;
            }
            completion([self takeTokenFromData:data ?: [NSData data]] ? nil
                       : [RAGarminConnect errorWithCode:RAGarminErrorBadAnswer status:status step:@"token" body:nil]);
        });
    }] resume];
}

// an API request with a valid token; a 401 gets a new token and one retry, a transient error (408, 429, 5xx) one
// retry after a delay. step: for the error messages. Completion on the main queue.
- (void)get:(NSURL *)url step:(NSString *)step completion:(void (^)(NSData * _Nullable data, NSError * _Nullable error))completion
{
    [self get:url step:step retried:NO completion:completion];
}

- (void)get:(NSURL *)url step:(NSString *)step retried:(BOOL)retried
 completion:(void (^)(NSData * _Nullable data, NSError * _Nullable error))completion
{
    if (!_token || [_tokenExpiry timeIntervalSinceNow] < 60) {
        [self obtainTokenWithCompletion:^(NSError *error) {
            if (error) completion(nil, error);
            else [self sendGet:url step:step retried:retried completion:completion];
        }];
    } else {
        [self sendGet:url step:step retried:retried completion:completion];
    }
}

- (void)sendGet:(NSURL *)url step:(NSString *)step retried:(BOOL)retried
     completion:(void (^)(NSData * _Nullable data, NSError * _Nullable error))completion
{
    NSMutableURLRequest *r = [RAEnvironment requestWithURL:url];
    [r setValue:[@"Bearer " stringByAppendingString:_token ?: @""] forHTTPHeaderField:@"Authorization"];
    [[_session dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) { completion(nil, error); return; }
            if (status == 401 && !retried) {
                self->_token = nil;
                [self get:url step:step retried:YES completion:completion];
                return;
            }
            if ([RAGarminConnect isTransientStatus:status] && !retried) {
                [self after:[self retryDelayForResponse:response] do:^{
                    [self get:url step:step retried:YES completion:completion];
                }];
                return;
            }
            if (status < 200 || status >= 300) {
                completion(nil, [RAGarminConnect errorWithCode:RAGarminErrorHTTP status:status step:step body:data]);
                return;
            }
            completion(data ?: [NSData data], nil);
        });
    }] resume];
}

+ (NSString *)dayString:(NSDate *)date
{
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyy-MM-dd";
    return [f stringFromDate:date];
}

- (void)activitiesFrom:(NSUInteger)start limit:(NSUInteger)limit startDate:(nullable NSDate *)startDate
     completion:(void (^)(NSArray<RAGarminActivity *> * _Nullable activities, NSError * _Nullable error))completion
{
    NSURLComponents *c = [NSURLComponents componentsWithURL:[[RAEnvironment garminAPIBaseURL]
        URLByAppendingPathComponent:@"activitylist-service/activities/search/activities"] resolvingAgainstBaseURL:NO];
    NSMutableArray<NSURLQueryItem *> *items = [@[
        [NSURLQueryItem queryItemWithName:@"start" value:[NSString stringWithFormat:@"%lu", (unsigned long)start]],
        [NSURLQueryItem queryItemWithName:@"limit" value:[NSString stringWithFormat:@"%lu", (unsigned long)limit]],
    ] mutableCopy];
    if (startDate) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"startDate" value:[RAGarminConnect dayString:startDate]]];
        [items addObject:[NSURLQueryItem queryItemWithName:@"endDate" value:[RAGarminConnect dayString:[NSDate date]]]];
    }
    c.queryItems = items;
    [self get:c.URL step:@"list" completion:^(NSData *data, NSError *error) {
        if (!data) { completion(nil, error); return; }
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if (![json isKindOfClass:[NSArray class]]) {
            completion(nil, [RAGarminConnect errorWithCode:RAGarminErrorBadAnswer status:0 step:@"list" body:data]);
            return;
        }
        NSMutableArray<RAGarminActivity *> *activities = [NSMutableArray array];
        for (id item in json) {
            RAGarminActivity *a = [RAGarminActivity activityWithJSON:item];
            if (a) [activities addObject:a];
        }
        completion(activities, nil);
    }];
}

- (void)gpxExportOfActivity:(NSString *)activityID
                 completion:(void (^)(NSData * _Nullable gpx, NSError * _Nullable error))completion
{
    NSURL *url = [[RAEnvironment garminAPIBaseURL] URLByAppendingPathComponent:
                  [@"download-service/export/gpx/activity/" stringByAppendingString:activityID]];
    [self get:url step:@"gpx" completion:^(NSData *data, NSError *error) {
        if (data.length) {
            completion(data, nil);
            return;
        }
        // the TCX export, which follows the cuts too
        NSURL *tcx = [[RAEnvironment garminAPIBaseURL] URLByAppendingPathComponent:
                      [@"download-service/export/tcx/activity/" stringByAppendingString:activityID]];
        [self get:tcx step:@"tcx" completion:^(NSData *tcxData, NSError *tcxError) {
            completion(tcxData.length ? tcxData : nil,
                       tcxData.length ? nil : (tcxError ?: error ?: [RAGarminConnect errorWithCode:RAGarminErrorBadAnswer status:0]));
        }];
    }];
}

- (void)fitFileOfActivity:(NSString *)activityID
     completion:(void (^)(NSData * _Nullable fit, NSError * _Nullable error))completion
{
    NSURL *url = [[RAEnvironment garminAPIBaseURL] URLByAppendingPathComponent:
                  [@"download-service/files/activity/" stringByAppendingString:activityID]];
    [self get:url step:@"download" completion:^(NSData *data, NSError *error) {
        if (!data) { completion(nil, error); return; }
        if (![RAZipReader isZipData:data]) { // already a FIT file
            completion(data.length ? data : nil, data.length ? nil : [RAGarminConnect errorWithCode:RAGarminErrorBadAnswer status:0]);
            return;
        }
        NSError *zipError = nil;
        NSDictionary<NSString *, NSData *> *entries = [RAZipReader entriesOfZipData:data error:&zipError];
        for (NSString *name in entries) {
            if ([name.pathExtension.lowercaseString isEqualToString:@"fit"]) { completion(entries[name], nil); return; }
        }
        completion(nil, zipError ?: [RAGarminConnect errorWithCode:RAGarminErrorBadAnswer status:0]);
    }];
}

@end
