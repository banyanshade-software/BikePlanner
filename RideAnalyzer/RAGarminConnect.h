//
//  RAGarminConnect.h
//  RideAnalyzer
//
//  Client of the Garmin Connect Personal API (#82, R1): the user's own activities, read-only.
//  - the Personal API key (created by the user in Garmin Connect, Settings ▸ Personal API token) is exchanged for a
//    bearer token, valid about 24 hours, with no refresh token: the exchange is done again when it expires;
//  - activities: GET <base>/activitylist-service/activities/search/activities?start=&limit=[&startDate=&endDate=]
//  - FIT file of an activity: GET <base>/download-service/files/activity/<id>, a ZIP holding the FIT file.
//  Sources: Garmin's Personal API page and its official Python client (garmin/connect-personal-api-python), see #82.
//  TO CHECK against the real service (not done when this was written, 2026-11-21): the API host, the shape of the
//  token answer, the fields of an activity. The endpoints can be overridden in the user defaults (RAEnvironment).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const RAGarminErrorDomain;
typedef NS_ENUM(NSInteger, RAGarminError) {
    RAGarminErrorNoKey = 1,
    RAGarminErrorKeyRejected,     // HTTP 401 / 403 on the token exchange: wrong or expired key
    RAGarminErrorHTTP,            // another HTTP status (userInfo RAGarminHTTPStatusKey)
    RAGarminErrorBadAnswer,       // unexpected answer (not JSON, no token, no FIT file in the archive)
};
extern NSString *const RAGarminHTTPStatusKey;
/// which request failed: @"token", @"list" or @"download" (the recovery suggestion of the error says it too)
extern NSString *const RAGarminStepKey;

/// endpoints and the identification of the app's requests; user defaults override the endpoints (tests, or if
/// Garmin moves them): RAGarminTokenURL, RAGarminAPIBaseURL
@interface RAEnvironment : NSObject
+ (NSURL *)garminTokenURL;
+ (NSURL *)garminAPIBaseURL;
/// "RideAnalyzer/<version> (+<GitHub URL>)"
+ (NSString *)userAgent;
+ (NSMutableURLRequest *)requestWithURL:(NSURL *)url;
@end

/// where the Personal API key of a library is kept: the login Keychain (generic password, one per library)
@protocol RAKeyStore <NSObject>
- (nullable NSString *)keyForLibrary:(NSString *)libraryID;
- (BOOL)setKey:(nullable NSString *)key forLibrary:(NSString *)libraryID;
@end

@interface RAKeychainKeyStore : NSObject <RAKeyStore>
+ (instancetype)shared;
@end

/// tests: in memory, never the user's Keychain
@interface RAMemoryKeyStore : NSObject <RAKeyStore>
@end

/// one activity of the list
@interface RAGarminActivity : NSObject
@property (copy, nonatomic) NSString *activityID;
@property (copy, nonatomic) NSString *name;
@property (nullable, copy, nonatomic) NSDate *startDate;   // startTimeGMT
@property (copy, nonatomic) NSString *typeKey;              // activityType.typeKey, e.g. road_biking
@property (nonatomic) double distance;                      // meters (as corrected in Garmin Connect)
@property (nonatomic) NSTimeInterval elapsedDuration;       // s, elapsedDuration, else duration; 0 when absent
/// nil when the dictionary has no activityId
+ (nullable instancetype)activityWithJSON:(NSDictionary *)json;
/// outdoor cycling (road, gravel, mountain, e-bike…): not indoor or virtual rides, which have no track
@property (readonly, nonatomic) BOOL isOutdoorCycling;
@end

@interface RAGarminConnect : NSObject

- (instancetype)initWithKey:(NSString *)apiKey session:(NSURLSession *)session NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// a page of activities, newest first; startDate / endDate: days (the API takes YYYY-MM-DD)
- (void)activitiesFrom:(NSUInteger)start limit:(NSUInteger)limit startDate:(nullable NSDate *)startDate
     completion:(void (^)(NSArray<RAGarminActivity *> * _Nullable activities, NSError * _Nullable error))completion;
/// the FIT file of an activity (taken out of the ZIP)
/// the GPX export of an activity, else its TCX export: unlike the original FIT file, they follow the cuts made in
/// Garmin Connect (owner's June 6 activity: FIT 276.7 km; GPX and TCX the 2.21 km and 6:55 kept, 04:52:27–04:59:22).
/// TO CHECK: the endpoints with the Personal API.
- (void)gpxExportOfActivity:(NSString *)activityID
                 completion:(void (^)(NSData * _Nullable gpx, NSError * _Nullable error))completion;
- (void)fitFileOfActivity:(NSString *)activityID
     completion:(void (^)(NSData * _Nullable fit, NSError * _Nullable error))completion;

/// seconds before the one retry of a transient error (HTTP 408, 429, 502–504) when the answer has no Retry-After;
/// 2 by default
@property (nonatomic) NSTimeInterval retryDelay;

/// the token in use (nil before the first request), for tests
@property (readonly, nonatomic, nullable) NSString *token;

/// the expiry of a JWT (its exp claim), nil if the string is not a JWT with exp
+ (nullable NSDate *)expiryOfJWT:(NSString *)token;

@end

NS_ASSUME_NONNULL_END
