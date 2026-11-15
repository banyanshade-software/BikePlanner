//
//  BPTrackReader.h
//  BikePlanner
//
//  Reads a track to import (#76): GPX (through GPXParser), TCX (Garmin Training Center XML, activity or course) or
//  FIT (Garmin binary format, through BPFITDecoder), recognized from the content, not the file name. Used by Import
//  Track as Display / as Route.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

NS_ASSUME_NONNULL_BEGIN

@interface BPTrackReader : NSObject

/// nil (and an error) for an empty, unreadable or malformed file; a well-formed file may give an empty trace
+ (nullable BPTrackReader *)readerWithData:(NSData *)data error:(NSError * _Nullable *)error;
+ (nullable BPTrackReader *)readerWithContentsOfURL:(NSURL *)url error:(NSError * _Nullable *)error;
/// the root element is TrainingCenterDatabase
+ (BOOL)isTCXData:(NSData *)data;
/// the FIT signature
+ (BOOL)isFITData:(NSData *)data;
/// types accepted by the import open panels: GPX, TCX, FIT
+ (NSArray<UTType *> *)importContentTypes;

/// @"gpx", @"tcx" or @"fit"
@property (readonly, nonatomic) NSString *format;
/// GPX: the track points, else the route points, else the waypoints; TCX: the trackpoints that have a position
/// (all laps, activities and courses, in order), with altitude and time; FIT: the records that have a position
/// (altitude 0 when the file has none)
@property (readonly, nonatomic) NSArray<CLLocation *> *trace;
/// what the trace is made of: @"trk", @"rte" or @"wpt" (GPX); always @"trk" for TCX and FIT
@property (readonly, nonatomic) NSString *traceSource;
/// GPX <wpt>; TCX <CoursePoint> / FIT course_point, except turn cues (left, right, straight…)
@property (readonly, nonatomic) NSArray<CLLocation *> *waypoints;
/// for each waypoint: its GPX <type>, or the GPX type of the custom POI matching the TCX PointType; @"" when none
@property (readonly, nonatomic) NSArray<NSString *> *waypointTypes;
/// for each waypoint: its name, @"" when none or when it is just its type (BikePlanner exports a nameless custom POI
/// with its type as name; TCX tools name course points after their type)
@property (readonly, nonatomic) NSArray<NSString *> *waypointNames;

@end

NS_ASSUME_NONNULL_END
