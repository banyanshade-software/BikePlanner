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
}

@end
