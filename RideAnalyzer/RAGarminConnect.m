//
//  RAGarminConnect.m
//  RideAnalyzer
//

#import "RAGarminConnect.h"
#import "RAZipReader.h"
#import <Security/Security.h>

NSString *const RAGarminErrorDomain = @"RAGarminConnect";
NSString *const RAGarminHTTPStatusKey = @"RAGarminHTTPStatus";

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
    }
    return self;
}

- (nullable NSString *)token
{
    return _token;
}

+ (NSError *)errorWithCode:(RAGarminError)code status:(NSInteger)status
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
    return [NSError errorWithDomain:RAGarminErrorDomain code:code userInfo:info];
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
    if (_apiKey.length == 0) {
        completion([RAGarminConnect errorWithCode:RAGarminErrorNoKey status:0]);
        return;
    }
    NSMutableURLRequest *r = [RAEnvironment requestWithURL:[RAEnvironment garminTokenURL]];
    r.HTTPMethod = @"POST";
    [r setValue:[@"ApiKey " stringByAppendingString:_apiKey] forHTTPHeaderField:@"Authorization"];
    [r setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [[_session dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) { completion(error); return; }
            if (status == 401 || status == 403) { completion([RAGarminConnect errorWithCode:RAGarminErrorKeyRejected status:status]); return; }
            if (status < 200 || status >= 300) { completion([RAGarminConnect errorWithCode:RAGarminErrorHTTP status:status]); return; }
            completion([self takeTokenFromData:data ?: [NSData data]] ? nil
                       : [RAGarminConnect errorWithCode:RAGarminErrorBadAnswer status:status]);
        });
    }] resume];
}

// an API request with a valid token; a 401 gets a new token and one retry. Completion on the main queue.
- (void)get:(NSURL *)url retried:(BOOL)retried completion:(void (^)(NSData * _Nullable data, NSError * _Nullable error))completion
{
    if (!_token || [_tokenExpiry timeIntervalSinceNow] < 60) {
        [self obtainTokenWithCompletion:^(NSError *error) {
            if (error) completion(nil, error);
            else [self sendGet:url retried:retried completion:completion];
        }];
    } else {
        [self sendGet:url retried:retried completion:completion];
    }
}

- (void)sendGet:(NSURL *)url retried:(BOOL)retried completion:(void (^)(NSData * _Nullable data, NSError * _Nullable error))completion
{
    NSMutableURLRequest *r = [RAEnvironment requestWithURL:url];
    [r setValue:[@"Bearer " stringByAppendingString:_token ?: @""] forHTTPHeaderField:@"Authorization"];
    [[_session dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) { completion(nil, error); return; }
            if (status == 401 && !retried) {
                self->_token = nil;
                [self get:url retried:YES completion:completion];
                return;
            }
            if (status < 200 || status >= 300) { completion(nil, [RAGarminConnect errorWithCode:RAGarminErrorHTTP status:status]); return; }
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
    [self get:c.URL retried:NO completion:^(NSData *data, NSError *error) {
        if (!data) { completion(nil, error); return; }
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if (![json isKindOfClass:[NSArray class]]) {
            completion(nil, [RAGarminConnect errorWithCode:RAGarminErrorBadAnswer status:0]);
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

- (void)fitFileOfActivity:(NSString *)activityID
     completion:(void (^)(NSData * _Nullable fit, NSError * _Nullable error))completion
{
    NSURL *url = [[RAEnvironment garminAPIBaseURL] URLByAppendingPathComponent:
                  [@"download-service/files/activity/" stringByAppendingString:activityID]];
    [self get:url retried:NO completion:^(NSData *data, NSError *error) {
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
