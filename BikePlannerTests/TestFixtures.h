//
//  TestFixtures.h
//  BikePlannerTests
//
//  Shared test data and helpers.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

// A small GPX as returned by brouter.de (format=gpx), including the statistics comment.
static NSString * const kBRouterGPX =
@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
@"<!-- track-length = 14994 filtered ascend = 168 plain-ascend = 27 cost=26496 energy=.1kwh time=57m 15s -->\n"
@"<gpx xmlns=\"http://www.topografix.com/GPX/1/1\" creator=\"BRouter-1.7.8\" version=\"1.1\">\n"
@" <trk>\n"
@"  <name>brouter_trekking_0</name>\n"
@"  <trkseg>\n"
@"   <trkpt lon=\"0.491229\" lat=\"44.193329\"><ele>140.25</ele></trkpt>\n"
@"   <trkpt lon=\"0.492000\" lat=\"44.194000\"><ele>145.5</ele></trkpt>\n"
@"   <trkpt lon=\"0.493000\" lat=\"44.195000\"><ele>143</ele></trkpt>\n"
@"  </trkseg>\n"
@" </trk>\n"
@"</gpx>\n";

static inline NSData *BPData(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }

static inline CLLocation *BPLoc(double lat, double lon) {
    return [[CLLocation alloc] initWithLatitude:lat longitude:lon];
}

static inline CLLocation *BPLocAlt(double lat, double lon, double alt) {
    return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon)
                                         altitude:alt
                               horizontalAccuracy:kCLLocationAccuracyBest
                                 verticalAccuracy:kCLLocationAccuracyBest
                                        timestamp:[NSDate date]];
}

NS_ASSUME_NONNULL_END
