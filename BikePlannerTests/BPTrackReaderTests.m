//
//  BPTrackReaderTests.m
//  BikePlannerTests
//
//  Reading the tracks to import: GPX and TCX (#76).
//

#import <XCTest/XCTest.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "BPTrackReader.h"
#import "TestFixtures.h"
#import "BPFITBuilder.h"
#import "BPFITDecoder.h"

// a TCX activity: two laps, a trackpoint without position (pause) between them
static NSString *const kTCXActivity =
    @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    @"<TrainingCenterDatabase xmlns=\"http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2\""
    @" xmlns:ns3=\"http://www.garmin.com/xmlschemas/ActivityExtension/v2\">"
    @"<Activities><Activity Sport=\"Biking\"><Id>2026-11-01T08:00:00Z</Id>"
    @"<Lap StartTime=\"2026-11-01T08:00:00Z\"><TotalTimeSeconds>60</TotalTimeSeconds><Track>"
    @"<Trackpoint><Time>2026-11-01T08:00:00Z</Time><Position><LatitudeDegrees>44.01</LatitudeDegrees>"
    @"<LongitudeDegrees>0.51</LongitudeDegrees></Position><AltitudeMeters>120.5</AltitudeMeters>"
    @"<Extensions><ns3:TPX><ns3:Speed>5.2</ns3:Speed></ns3:TPX></Extensions></Trackpoint>"
    @"<Trackpoint><Time>2026-11-01T08:00:10.500Z</Time><Position><LatitudeDegrees>44.02</LatitudeDegrees>"
    @"<LongitudeDegrees>0.52</LongitudeDegrees></Position><AltitudeMeters>125</AltitudeMeters></Trackpoint>"
    @"<Trackpoint><Time>2026-11-01T08:00:20Z</Time><HeartRateBpm><Value>120</Value></HeartRateBpm></Trackpoint>"
    @"</Track></Lap>"
    @"<Lap StartTime=\"2026-11-01T08:01:00Z\"><Track>"
    @"<Trackpoint><Time>2026-11-01T08:01:00Z</Time><Position><LatitudeDegrees>44.03</LatitudeDegrees>"
    @"<LongitudeDegrees>0.53</LongitudeDegrees></Position></Trackpoint>"
    @"</Track></Lap></Activity></Activities></TrainingCenterDatabase>";

// a TCX course: 3 trackpoints, course points of several types (turn cues are skipped)
static NSString *const kTCXCourse =
    @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    @"<TrainingCenterDatabase xmlns=\"http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2\">"
    @"<Courses><Course><Name>My course</Name><Lap><TotalTimeSeconds>0</TotalTimeSeconds></Lap><Track>"
    @"<Trackpoint><Position><LatitudeDegrees>45.1</LatitudeDegrees><LongitudeDegrees>1.1</LongitudeDegrees></Position></Trackpoint>"
    @"<Trackpoint><Position><LatitudeDegrees>45.2</LatitudeDegrees><LongitudeDegrees>1.2</LongitudeDegrees></Position></Trackpoint>"
    @"<Trackpoint><Position><LatitudeDegrees>45.3</LatitudeDegrees><LongitudeDegrees>1.3</LongitudeDegrees></Position></Trackpoint>"
    @"</Track>"
    @"<CoursePoint><Name>Fountain</Name><Position><LatitudeDegrees>45.11</LatitudeDegrees><LongitudeDegrees>1.11</LongitudeDegrees></Position><PointType>Water</PointType></CoursePoint>"
    @"<CoursePoint><Name>Left</Name><Position><LatitudeDegrees>45.12</LatitudeDegrees><LongitudeDegrees>1.12</LongitudeDegrees></Position><PointType>Left</PointType></CoursePoint>"
    @"<CoursePoint><Name>Food</Name><Position><LatitudeDegrees>45.13</LatitudeDegrees><LongitudeDegrees>1.13</LongitudeDegrees></Position><PointType>Food</PointType></CoursePoint>"
    @"<CoursePoint><Name>Steep descent</Name><Position><LatitudeDegrees>45.14</LatitudeDegrees><LongitudeDegrees>1.14</LongitudeDegrees></Position><PointType>Danger</PointType></CoursePoint>"
    @"<CoursePoint><Name>Col</Name><Position><LatitudeDegrees>45.15</LatitudeDegrees><LongitudeDegrees>1.15</LongitudeDegrees></Position><PointType>Summit</PointType></CoursePoint>"
    @"<CoursePoint><Name>Pharmacy</Name><Position><LatitudeDegrees>45.16</LatitudeDegrees><LongitudeDegrees>1.16</LongitudeDegrees></Position><PointType>First Aid</PointType></CoursePoint>"
    @"<CoursePoint><Name>Straight</Name><Position><LatitudeDegrees>45.17</LatitudeDegrees><LongitudeDegrees>1.17</LongitudeDegrees></Position><PointType>Straight</PointType></CoursePoint>"
    @"<CoursePoint><Position><LatitudeDegrees>45.18</LatitudeDegrees><LongitudeDegrees>1.18</LongitudeDegrees></Position><PointType>Generic</PointType></CoursePoint>"
    @"</Course></Courses></TrainingCenterDatabase>";

@interface BPTrackReaderTests : XCTestCase
@end

@implementation BPTrackReaderTests

- (void)testReadsTCXActivity
{
    NSError *err = nil;
    BPTrackReader *r = [BPTrackReader readerWithData:BPData(kTCXActivity) error:&err];
    XCTAssertNotNil(r, @"%@", err);
    XCTAssertEqualObjects(r.format, @"tcx");
    XCTAssertEqualObjects(r.traceSource, @"trk");
    XCTAssertEqual(r.trace.count, 3u, @"both laps, the trackpoint without position is skipped");
    XCTAssertEqualWithAccuracy(r.trace[0].coordinate.latitude, 44.01, 1e-9);
    XCTAssertEqualWithAccuracy(r.trace[0].coordinate.longitude, 0.51, 1e-9);
    XCTAssertEqualWithAccuracy(r.trace[0].altitude, 120.5, 1e-9);
    XCTAssertEqualWithAccuracy(r.trace[1].altitude, 125, 1e-9);
    XCTAssertEqualWithAccuracy(r.trace[2].coordinate.latitude, 44.03, 1e-9);
    NSDate *t0 = [[[NSISO8601DateFormatter alloc] init] dateFromString:@"2026-11-01T08:00:00Z"];
    XCTAssertEqualObjects(r.trace[0].timestamp, t0, @"the time of the trackpoint");
    XCTAssertEqualWithAccuracy([r.trace[1].timestamp timeIntervalSinceDate:r.trace[0].timestamp], 10.5, 1e-3, @"fractional seconds");
    XCTAssertEqual(r.waypoints.count, 0u);
}

- (void)testReadsTCXCourseWithCoursePoints
{
    BPTrackReader *r = [BPTrackReader readerWithData:BPData(kTCXCourse) error:NULL];
    XCTAssertEqualObjects(r.format, @"tcx");
    XCTAssertEqualObjects(r.traceSource, @"trk", @"a course track is a track (simplified when imported as route)");
    XCTAssertEqual(r.trace.count, 3u);
    XCTAssertEqual(r.waypoints.count, 6u, @"Left and Straight (turn cues) are skipped");
    XCTAssertEqual(r.waypointTypes.count, 6u);
    XCTAssertEqual(r.waypointNames.count, 6u);
    NSArray *types = @[ @"WATER", @"FOOD", @"DANGER", @"OVERLOOK", @"INFO", @"" ];
    XCTAssertEqualObjects(r.waypointTypes, types, @"TCX point types mapped to the GPX types of the custom POIs");
    NSArray *names = @[ @"Fountain", @"", @"Steep descent", @"Col", @"Pharmacy", @"" ];
    XCTAssertEqualObjects(r.waypointNames, names, @"a name equal to the point type is not a name");
    XCTAssertEqualWithAccuracy(r.waypoints[2].coordinate.latitude, 45.14, 1e-9);
    XCTAssertEqualWithAccuracy(r.waypoints[2].coordinate.longitude, 1.14, 1e-9);
}

- (void)testReadsGPXWithWaypointNames
{
    NSString *gpx = @"<gpx><trk><name>track</name><trkseg><trkpt lat=\"1\" lon=\"2\"/><trkpt lat=\"1.1\" lon=\"2.1\"/></trkseg></trk>"
                    @"<wpt lat=\"1.05\" lon=\"2.05\"><name>DANGER</name><type>DANGER</type></wpt>"
                    @"<wpt lat=\"1.06\" lon=\"2.06\"><name> Bridge </name><type>Danger</type></wpt>"
                    @"<wpt lat=\"1.07\" lon=\"2.07\"></wpt></gpx>";
    BPTrackReader *r = [BPTrackReader readerWithData:BPData(gpx) error:NULL];
    XCTAssertEqualObjects(r.format, @"gpx");
    XCTAssertEqualObjects(r.traceSource, @"trk");
    XCTAssertEqual(r.trace.count, 2u);
    XCTAssertEqual(r.waypoints.count, 3u);
    NSArray *types = @[ @"DANGER", @"Danger", @"" ];
    XCTAssertEqualObjects(r.waypointTypes, types);
    NSArray *names = @[ @"", @"Bridge", @"" ];
    XCTAssertEqualObjects(r.waypointNames, names, @"the name BikePlanner exports for a nameless custom POI is its type");
}

- (void)testFormatIsDetectedFromTheContent
{
    XCTAssertTrue([BPTrackReader isTCXData:BPData(kTCXCourse)]);
    XCTAssertFalse([BPTrackReader isTCXData:BPData(kBRouterGPX)]);
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"bp-misnamed.gpx"]];
    XCTAssertTrue([BPData(kTCXActivity) writeToURL:url atomically:YES]);
    BPTrackReader *r = [BPTrackReader readerWithContentsOfURL:url error:NULL];
    XCTAssertEqualObjects(r.format, @"tcx", @"a TCX file named .gpx is read as TCX");
    XCTAssertEqual(r.trace.count, 3u);
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
}

- (void)testMalformedOrEmptyFiles
{
    NSError *err = nil;
    XCTAssertNil([BPTrackReader readerWithData:BPData(@"<TrainingCenterDatabase><Courses>") error:&err]);
    XCTAssertNotNil(err);
    err = nil;
    XCTAssertNil([BPTrackReader readerWithData:[NSData data] error:&err]);
    XCTAssertNotNil(err);
    err = nil;
    XCTAssertNil([BPTrackReader readerWithContentsOfURL:[NSURL fileURLWithPath:@"/nonexistent/x.tcx"] error:&err]);
    XCTAssertNotNil(err);
    // well-formed, no position: an empty trace (the imports then do nothing)
    BPTrackReader *r = [BPTrackReader readerWithData:BPData(@"<TrainingCenterDatabase><Activities><Activity><Lap><Track>"
                                                            @"<Trackpoint><Time>2026-11-01T08:00:00Z</Time></Trackpoint>"
                                                            @"</Track></Lap></Activity></Activities></TrainingCenterDatabase>") error:NULL];
    XCTAssertNotNil(r);
    XCTAssertEqual(r.trace.count, 0u);
}

- (void)testImportContentTypes
{
    NSArray<UTType *> *types = [BPTrackReader importContentTypes];
    XCTAssertTrue([types containsObject:[UTType typeWithFilenameExtension:@"gpx"]]);
    XCTAssertTrue([types containsObject:[UTType typeWithFilenameExtension:@"tcx"]]);
    XCTAssertTrue([types containsObject:[UTType typeWithFilenameExtension:@"fit"]]);
}

#pragma mark - FIT

static const int32_t kNoPos = 0x7FFFFFFF;

// a FIT activity covering what real files contain: file_id, records with a developer field, a record without
// position, a big-endian redefinition with enhanced_altitude, compressed timestamps, an unknown message
- (NSData *)fitActivity
{
    BPFITBuilder *b = [[BPFITBuilder alloc] init];
    NSDate *t0 = [NSDate dateWithTimeIntervalSince1970:1762000000]; // 2025-11-01
    uint32_t ts = [BPFITBuilder fitTimestamp:t0];
    // file_id: type activity
    [b defineLocal:0 global:0 fields:@[ @[ @0, @1, @(BPFITEnum) ], @[ @1, @2, @(BPFITUInt16) ] ]];
    [b dataLocal:0 values:@[ @4, @1 ]];
    // unknown message 233 with a string
    [b defineLocal:1 global:233 fields:@[ @[ @2, @3, @(BPFITUInt8) ], @[ @3, @5, @(BPFITString) ] ]];
    [b dataLocal:1 values:@[ @7, @"abcd" ]];
    // record: timestamp, lat, lon, altitude, + a 2-byte developer field
    [b defineLocal:2 global:20 fields:@[ @[ @253, @4, @(BPFITUInt32) ], @[ @0, @4, @(BPFITSInt32) ],
                                         @[ @1, @4, @(BPFITSInt32) ], @[ @2, @2, @(BPFITUInt16) ] ]
         bigEndian:NO developerSizes:@[ @2 ]];
    [b dataLocal:2 values:@[ @(ts), @([BPFITBuilder semicircles:44.01]), @([BPFITBuilder semicircles:0.51]), @((120.4 + 500) * 5) ]];
    [b dataLocal:2 values:@[ @(ts + 5), @(kNoPos), @(kNoPos), @0xFFFF ]]; // GPS lost
    [b dataLocal:1 values:@[ @9, @"xyz" ]];
    // big-endian redefinition of local 2: enhanced_altitude, no altitude
    [b defineLocal:2 global:20 fields:@[ @[ @253, @4, @(BPFITUInt32) ], @[ @0, @4, @(BPFITSInt32) ],
                                         @[ @1, @4, @(BPFITSInt32) ], @[ @78, @4, @(BPFITUInt32) ] ]
         bigEndian:YES developerSizes:nil];
    [b dataLocal:2 values:@[ @(ts + 10), @([BPFITBuilder semicircles:44.02]), @([BPFITBuilder semicircles:-0.52]), @((1250.2 + 500) * 5) ]];
    // compressed timestamps: a record without timestamp field and without altitude
    [b defineLocal:3 global:20 fields:@[ @[ @0, @4, @(BPFITSInt32) ], @[ @1, @4, @(BPFITSInt32) ] ]];
    uint8_t low = (ts + 10) & 0x1F;
    [b compressedLocal:3 timeOffset:(low + 3) & 0x1F values:@[ @([BPFITBuilder semicircles:44.03]), @([BPFITBuilder semicircles:0.53]) ]];
    return b.data;
}

- (void)testReadsFITActivity
{
    NSError *err = nil;
    BPTrackReader *r = [BPTrackReader readerWithData:[self fitActivity] error:&err];
    XCTAssertNotNil(r, @"%@", err);
    XCTAssertEqualObjects(r.format, @"fit");
    XCTAssertEqualObjects(r.traceSource, @"trk");
    XCTAssertEqual(r.trace.count, 3u, @"the record without position is skipped");
    XCTAssertEqualWithAccuracy(r.trace[0].coordinate.latitude, 44.01, 1e-6);
    XCTAssertEqualWithAccuracy(r.trace[0].coordinate.longitude, 0.51, 1e-6);
    XCTAssertEqualWithAccuracy(r.trace[0].altitude, 120.4, 0.1);
    XCTAssertEqualObjects(r.trace[0].timestamp, [NSDate dateWithTimeIntervalSince1970:1762000000]);
    XCTAssertEqualWithAccuracy(r.trace[1].coordinate.longitude, -0.52, 1e-6, @"big-endian, negative");
    XCTAssertEqualWithAccuracy(r.trace[1].altitude, 1250.2, 0.1, @"enhanced_altitude");
    XCTAssertEqualWithAccuracy(r.trace[2].coordinate.latitude, 44.03, 1e-6);
    XCTAssertEqual(r.trace[2].altitude, 0, @"no altitude field");
    XCTAssertEqualWithAccuracy([r.trace[2].timestamp timeIntervalSinceDate:r.trace[1].timestamp], 3, 1e-9, @"compressed timestamp");
    XCTAssertEqual(r.waypoints.count, 0u);
    XCTAssertTrue(r.hasTimes);
    XCTAssertEqualObjects(r.deviceManufacturer, @1, @"file_id manufacturer: Garmin");
    XCTAssertNil(r.deviceProduct);
    XCTAssertNil(r.deviceSerialNumber);
    XCTAssertNil(r.sport, @"no sport or session message");
}

// which device recorded a FIT activity, and its sport (Ride Analyzer, #82)
- (void)testFITDeviceAndSport
{
    NSDate *t0 = [NSDate dateWithTimeIntervalSince1970:1795000000];
    uint32_t ts = [BPFITBuilder fitTimestamp:t0];
    BPFITBuilder *b = [[BPFITBuilder alloc] init];
    // file_id: type, manufacturer, product, serial_number (uint32z), time_created
    [b defineLocal:0 global:0 fields:@[ @[ @0, @1, @(BPFITEnum) ], @[ @1, @2, @(BPFITUInt16) ], @[ @2, @2, @(BPFITUInt16) ],
                                         @[ @3, @4, @(BPFITUInt32z) ], @[ @4, @4, @(BPFITUInt32) ] ]];
    [b dataLocal:0 values:@[ @4, @1, @3122, @3337123456, @(ts) ]];
    [b defineLocal:1 global:20 fields:@[ @[ @253, @4, @(BPFITUInt32) ], @[ @0, @4, @(BPFITSInt32) ], @[ @1, @4, @(BPFITSInt32) ] ]];
    [b dataLocal:1 values:@[ @(ts), @([BPFITBuilder semicircles:45]), @([BPFITBuilder semicircles:5]) ]];
    [b dataLocal:1 values:@[ @(ts + 1), @([BPFITBuilder semicircles:45.001]), @([BPFITBuilder semicircles:5]) ]];
    // session: timestamp, sport (cycling), sub_sport
    [b defineLocal:2 global:18 fields:@[ @[ @253, @4, @(BPFITUInt32) ], @[ @5, @1, @(BPFITEnum) ], @[ @6, @1, @(BPFITEnum) ] ]];
    [b dataLocal:2 values:@[ @(ts + 2), @2, @7 ]];
    BPTrackReader *r = [BPTrackReader readerWithData:b.data error:NULL];
    XCTAssertEqualObjects(r.deviceManufacturer, @1);
    XCTAssertEqualObjects(r.deviceProduct, @3122);
    XCTAssertEqualObjects(r.deviceSerialNumber, @3337123456);
    XCTAssertEqualObjects(r.sport, @"cycling");
    XCTAssertNil(r.deviceName, @"a FIT file has no device name");

    BPFITDecoder *d = [[BPFITDecoder alloc] init];
    XCTAssertTrue([d decodeData:b.data error:NULL]);
    XCTAssertEqualObjects(d.fileType, @4);
    XCTAssertEqualObjects(d.timeCreated, t0);
    XCTAssertEqualObjects(d.sport, @2);

    // a serial number 0 (uint32z invalid value) is no serial number; a record without timestamp: not all timed
    BPFITBuilder *b2 = [[BPFITBuilder alloc] init];
    [b2 defineLocal:0 global:0 fields:@[ @[ @0, @1, @(BPFITEnum) ], @[ @3, @4, @(BPFITUInt32z) ] ]];
    [b2 dataLocal:0 values:@[ @4, @0 ]];
    [b2 defineLocal:1 global:20 fields:@[ @[ @0, @4, @(BPFITSInt32) ], @[ @1, @4, @(BPFITSInt32) ] ]];
    [b2 dataLocal:1 values:@[ @([BPFITBuilder semicircles:45]), @([BPFITBuilder semicircles:5]) ]];
    r = [BPTrackReader readerWithData:b2.data error:NULL];
    XCTAssertNotNil(r);
    XCTAssertNil(r.deviceSerialNumber);
    XCTAssertFalse(r.hasTimes);
}

// heart rate, cadence, speed, power, temperature and calories (Ride Analyzer, #82)
- (void)testFITMetrics
{
    NSDate *t0 = [NSDate dateWithTimeIntervalSince1970:1795000000];
    uint32_t ts = [BPFITBuilder fitTimestamp:t0];
    BPFITBuilder *b = [[BPFITBuilder alloc] init];
    // record: timestamp, lat, lon, heart_rate, cadence, speed, power, temperature
    [b defineLocal:0 global:20 fields:@[ @[ @253, @4, @(BPFITUInt32) ], @[ @0, @4, @(BPFITSInt32) ], @[ @1, @4, @(BPFITSInt32) ],
                                         @[ @3, @1, @(BPFITUInt8) ], @[ @4, @1, @(BPFITUInt8) ], @[ @6, @2, @(BPFITUInt16) ],
                                         @[ @7, @2, @(BPFITUInt16) ], @[ @13, @1, @(0x01) ] ]];
    [b dataLocal:0 values:@[ @(ts), @([BPFITBuilder semicircles:45]), @([BPFITBuilder semicircles:5]),
                             @142, @88, @8250, @215, @(-3) ]];
    [b dataLocal:0 values:@[ @(ts + 1), @([BPFITBuilder semicircles:45.001]), @([BPFITBuilder semicircles:5]),
                             @0xFF, @0xFF, @0xFFFF, @0xFFFF, @0x7F ]]; // all invalid
    // session: total_calories, total_ascent
    [b defineLocal:1 global:18 fields:@[ @[ @253, @4, @(BPFITUInt32) ], @[ @11, @2, @(BPFITUInt16) ],
                                         @[ @22, @2, @(BPFITUInt16) ] ]];
    [b dataLocal:1 values:@[ @(ts + 2), @640, @412 ]];
    BPTrackReader *r = [BPTrackReader readerWithData:b.data error:NULL];
    XCTAssertEqual(r.metrics.count, r.trace.count);
    NSDictionary *m = r.metrics[0];
    XCTAssertEqualObjects(m[@"hr"], @142);
    XCTAssertEqualObjects(m[@"cadence"], @88);
    XCTAssertEqualWithAccuracy([m[@"speed"] doubleValue], 8.25, 1e-9, @"m/s, scale 1000");
    XCTAssertEqualObjects(m[@"power"], @215);
    XCTAssertEqualObjects(m[@"temperature"], @(-3));
    XCTAssertEqual([r.metrics[1] count], 0u, @"invalid values are left out");
    XCTAssertEqualObjects(r.calories, @640);
    XCTAssertEqualObjects(r.deviceAscent, @412, @"the gain computed by the device");
}

- (void)testTCXMetrics
{
    NSString *tcx = @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<TrainingCenterDatabase xmlns=\"http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2\""
        @" xmlns:ns3=\"http://www.garmin.com/xmlschemas/ActivityExtension/v2\">"
        @"<Activities><Activity Sport=\"Biking\"><Id>2026-11-16T08:00:00Z</Id>"
        @"<Lap StartTime=\"2026-11-16T08:00:00Z\"><Calories>300</Calories><Track>"
        @"<Trackpoint><Time>2026-11-16T08:00:00Z</Time><Position><LatitudeDegrees>45</LatitudeDegrees>"
        @"<LongitudeDegrees>5</LongitudeDegrees></Position><HeartRateBpm><Value>131</Value></HeartRateBpm>"
        @"<Cadence>85</Cadence><Extensions><ns3:TPX><ns3:Speed>7.5</ns3:Speed><ns3:Watts>190</ns3:Watts></ns3:TPX>"
        @"</Extensions></Trackpoint>"
        @"<Trackpoint><Time>2026-11-16T08:00:05Z</Time><Position><LatitudeDegrees>45.001</LatitudeDegrees>"
        @"<LongitudeDegrees>5</LongitudeDegrees></Position></Trackpoint>"
        @"</Track></Lap><Lap StartTime=\"2026-11-16T09:00:00Z\"><Calories>150</Calories></Lap>"
        @"</Activity></Activities></TrainingCenterDatabase>";
    BPTrackReader *r = [BPTrackReader readerWithData:BPData(tcx) error:NULL];
    XCTAssertEqual(r.metrics.count, 2u);
    XCTAssertEqualObjects(r.metrics[0], (@{ @"hr": @131, @"cadence": @85, @"speed": @7.5, @"power": @190 }));
    XCTAssertEqual([r.metrics[1] count], 0u);
    XCTAssertEqualObjects(r.calories, @450, @"the laps add up");

    r = [BPTrackReader readerWithData:BPData(kBRouterGPX) error:NULL];
    XCTAssertEqual(r.metrics.count, r.trace.count, @"GPX: one empty entry per point");
    XCTAssertNil(r.calories);
}

// the device and sport of a TCX activity (#82): Creator Name, UnitId, ProductID; Activity Sport
- (void)testTCXDeviceAndSport
{
    NSString *tcx = @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<TrainingCenterDatabase xmlns=\"http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2\""
        @" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">"
        @"<Activities><Activity Sport=\"Biking\"><Id>2026-11-16T08:00:00Z</Id>"
        @"<Lap StartTime=\"2026-11-16T08:00:00Z\"><Track>"
        @"<Trackpoint><Time>2026-11-16T08:00:00Z</Time><Position><LatitudeDegrees>45</LatitudeDegrees>"
        @"<LongitudeDegrees>5</LongitudeDegrees></Position></Trackpoint>"
        @"<Trackpoint><Time>2026-11-16T08:00:05Z</Time><Position><LatitudeDegrees>45.001</LatitudeDegrees>"
        @"<LongitudeDegrees>5</LongitudeDegrees></Position></Trackpoint>"
        @"</Track></Lap>"
        @"<Creator xsi:type=\"Device_t\"><Name>Edge 830</Name><UnitId>3337123456</UnitId><ProductID>3122</ProductID>"
        @"<Version><VersionMajor>9</VersionMajor><VersionMinor>10</VersionMinor></Version></Creator>"
        @"</Activity></Activities>"
        @"<Author xsi:type=\"Application_t\"><Name>Garmin Connect</Name></Author></TrainingCenterDatabase>";
    BPTrackReader *r = [BPTrackReader readerWithData:BPData(tcx) error:NULL];
    XCTAssertEqual(r.trace.count, 2u);
    XCTAssertTrue(r.hasTimes);
    XCTAssertEqualObjects(r.deviceName, @"Edge 830", @"not the Author's name");
    XCTAssertEqualObjects(r.deviceSerialNumber, @3337123456);
    XCTAssertEqualObjects(r.deviceProduct, @3122);
    XCTAssertEqualObjects(r.sport, @"cycling");

    r = [BPTrackReader readerWithData:BPData(kTCXCourse) error:NULL];
    XCTAssertFalse(r.hasTimes, @"a course has no times");
    XCTAssertNil(r.deviceName);
}

// compressed timestamp offset smaller than the low bits of the last timestamp: the 32 s rollover
- (void)testFITCompressedTimestampRollover
{
    BPFITBuilder *b = [[BPFITBuilder alloc] init];
    uint32_t ts = 1000000000 | 0x1E; // low 5 bits: 30
    [b defineLocal:0 global:20 fields:@[ @[ @253, @4, @(BPFITUInt32) ], @[ @0, @4, @(BPFITSInt32) ], @[ @1, @4, @(BPFITSInt32) ] ]];
    [b dataLocal:0 values:@[ @(ts), @([BPFITBuilder semicircles:1]), @([BPFITBuilder semicircles:2]) ]];
    [b defineLocal:1 global:20 fields:@[ @[ @0, @4, @(BPFITSInt32) ], @[ @1, @4, @(BPFITSInt32) ] ]];
    [b compressedLocal:1 timeOffset:2 values:@[ @([BPFITBuilder semicircles:1.1]), @([BPFITBuilder semicircles:2.1]) ]];
    BPTrackReader *r = [BPTrackReader readerWithData:b.data error:NULL];
    XCTAssertEqual(r.trace.count, 2u);
    XCTAssertEqualWithAccuracy([r.trace[1].timestamp timeIntervalSinceDate:r.trace[0].timestamp], 4, 1e-9, @"30 → 34 (offset 2)");
}

- (void)testReadsFITCourseWithCoursePoints
{
    BPFITBuilder *b = [[BPFITBuilder alloc] init];
    [b defineLocal:0 global:0 fields:@[ @[ @0, @1, @(BPFITEnum) ] ]];
    [b dataLocal:0 values:@[ @6 ]]; // course
    [b defineLocal:1 global:20 fields:@[ @[ @0, @4, @(BPFITSInt32) ], @[ @1, @4, @(BPFITSInt32) ] ]];
    for (int i = 0; i < 3; i++) [b dataLocal:1 values:@[ @([BPFITBuilder semicircles:45.1 + i * 0.1]), @([BPFITBuilder semicircles:1.1 + i * 0.1]) ]];
    // course_point: timestamp, lat, lon, type, name
    [b defineLocal:2 global:32 fields:@[ @[ @1, @4, @(BPFITUInt32) ], @[ @2, @4, @(BPFITSInt32) ], @[ @3, @4, @(BPFITSInt32) ],
                                         @[ @5, @1, @(BPFITEnum) ], @[ @6, @16, @(BPFITString) ] ]];
    NSArray *points = @[ @[ @3, @"Fountain" ], @[ @6, @"Left" ], @[ @4, @"" ], @[ @5, @"Steep descent" ], @[ @1, @"Col" ],
                         @[ @19, @"" ], @[ @0, @"Bakery" ], @[ @0xFF, @"" ] ];
    [points enumerateObjectsUsingBlock:^(NSArray *p, NSUInteger i, BOOL *stop) {
        [b dataLocal:2 values:@[ @1, @([BPFITBuilder semicircles:45.11 + i * 0.01]), @([BPFITBuilder semicircles:1.11]), p[0], p[1] ]];
    }];
    NSError *err = nil;
    BPTrackReader *r = [BPTrackReader readerWithData:b.data error:&err];
    XCTAssertNotNil(r, @"%@", err);
    XCTAssertEqual(r.trace.count, 3u);
    XCTAssertEqual(r.waypoints.count, 6u, @"turn cues (left, slight left) are skipped");
    NSArray *types = @[ @"WATER", @"FOOD", @"DANGER", @"OVERLOOK", @"", @"" ];
    XCTAssertEqualObjects(r.waypointTypes, types);
    NSArray *names = @[ @"Fountain", @"", @"Steep descent", @"Col", @"Bakery", @"" ];
    XCTAssertEqualObjects(r.waypointNames, names);
    XCTAssertEqualWithAccuracy(r.waypoints[2].coordinate.latitude, 45.14, 1e-6);
}

- (void)testFITWithoutPositionGivesAnEmptyTrace
{
    BPFITBuilder *b = [[BPFITBuilder alloc] init];
    [b defineLocal:0 global:20 fields:@[ @[ @253, @4, @(BPFITUInt32) ], @[ @0, @4, @(BPFITSInt32) ], @[ @1, @4, @(BPFITSInt32) ] ]];
    for (int i = 0; i < 5; i++) [b dataLocal:0 values:@[ @(1000000000 + i), @(kNoPos), @(kNoPos) ]];
    BPTrackReader *r = [BPTrackReader readerWithData:b.data error:NULL];
    XCTAssertNotNil(r);
    XCTAssertEqual(r.trace.count, 0u);
}

- (void)testRejectsBadFIT
{
    NSData *good = [self fitActivity];
    XCTAssertTrue([BPTrackReader isFITData:good]);
    XCTAssertFalse([BPTrackReader isFITData:BPData(kTCXCourse)]);
    NSError *err = nil;

    NSMutableData *badCRC = [good mutableCopy];
    ((uint8_t *)badCRC.mutableBytes)[40] ^= 0x55;
    XCTAssertNil([BPTrackReader readerWithData:badCRC error:&err], @"corrupted data");
    XCTAssertNotNil(err);

    err = nil;
    XCTAssertNil([BPTrackReader readerWithData:[good subdataWithRange:NSMakeRange(0, good.length - 30)] error:&err], @"truncated");
    XCTAssertNotNil(err);

    // a data message whose local type has no definition
    BPFITBuilder *b = [[BPFITBuilder alloc] init];
    [b defineLocal:0 global:20 fields:@[ @[ @0, @4, @(BPFITSInt32) ], @[ @1, @4, @(BPFITSInt32) ] ]];
    [b dataLocal:0 values:@[ @1, @2 ]];
    NSMutableData *undefined = [[b data] mutableCopy];
    // replace the data header (local 0) by local 5, then fix the CRC
    NSUInteger dataHeader = 14 + 1 + 5 + 2 * 3; // file header, then the definition: record header, 5 bytes, 2 fields
    ((uint8_t *)undefined.mutableBytes)[dataHeader] = 5;
    uint16_t crc = [BPFITBuilder crcOfData:[undefined subdataWithRange:NSMakeRange(0, undefined.length - 2)]];
    [undefined replaceBytesInRange:NSMakeRange(undefined.length - 2, 2) withBytes:&crc];
    err = nil;
    XCTAssertNil([BPTrackReader readerWithData:undefined error:&err], @"undefined local message type");
    XCTAssertNotNil(err);
}

@end
