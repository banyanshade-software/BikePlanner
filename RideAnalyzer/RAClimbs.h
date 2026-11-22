//
//  RAClimbs.h
//  RideAnalyzer
//
//  Climbs (#82, R7). Detection in a ride: from a low point to a high point, the climb going on as long as the road
//  does not go down more than a tolerance (10 m, or a quarter of the gain so far), from where the road last leaves the
//  bottom (within 1.5 m: a flat or a bump before the climb is not part of it); kept when it gains at least 30 m
//  over 300 m or more, at 3 % or more on average. Each climb keeps its figures (stats of its intervals: time, heart
//  rate, measured power and the work sums of the estimated power, R11), computed once with the stats of the ride
//  (RARideStats.climbs).
//  The same climb ridden again: the climbs of a set of rides are grouped when they start and end within 150 m of
//  each other (and their lengths differ by less than 15 %); a group lists its passages by date (best time, trend).
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "RAPower.h"

@class RARideAnalysis, RATerrainStats, RARide, RACancellation;

NS_ASSUME_NONNULL_BEGIN

@interface RAClimb : NSObject
@property (nonatomic) CLLocationCoordinate2D start;
@property (nonatomic) CLLocationCoordinate2D end;
@property (nonatomic) double startDistance;     // m from the start of the ride
@property (nonatomic) double length;            // m
@property (nonatomic) double gain;              // m, top minus bottom
@property (nonatomic) double maxGradient;       // %, over about 100 m
@property (strong, nonatomic) RATerrainStats *stats;   // its moving intervals
/// %
@property (readonly, nonatomic) double averageGradient;
/// s, the moving time (NaN without times)
@property (readonly, nonatomic) double time;
/// m/h (NaN without times)
@property (readonly, nonatomic) double climbingSpeed;
- (NSDictionary *)propertyList;
+ (nullable RAClimb *)climbWithPropertyList:(nullable id)plist;
/// starts and ends near the other's start and end, similar length: the same climb
- (BOOL)isSameClimbAs:(RAClimb *)other;
@end

@interface RAClimbDetector : NSObject
/// the climbs of a ride, in order; wind: for the air drag of the estimated power (R11, R12), nil: still air
+ (NSArray<RAClimb *> *)climbsOfAnalysis:(RARideAnalysis *)analysis wind:(nullable RAWindProvider)wind;
@end

/// one passage on a climb: a ride and its climb
@interface RAClimbPassage : NSObject
@property (weak, nonatomic, nullable) RARide *ride;
@property (strong, nonatomic) RAClimb *climb;
@property (copy, nonatomic, nullable) NSDate *date;
@end

/// a climb ridden one or more times
@interface RAClimbGroup : NSObject
/// oldest first
@property (readonly, nonatomic) NSArray<RAClimbPassage *> *passages;
/// the first passage's climb: where it starts and ends
@property (readonly, nonatomic) RAClimb *reference;
/// fastest passage (moving time), nil when no passage has times
@property (readonly, nonatomic, nullable) RAClimbPassage *best;
/// a name given by the user (RALibraryDocument climb names), else @"" (shown as "Climb at km x of <ride>")
@property (copy, nonatomic) NSString *name;
/// groups of the climbs of the rides, the most ridden first
+ (NSArray<RAClimbGroup *> *)groupsOfRides:(NSArray<RARide *> *)rides;
/// the same, stopped early (nil) when the cancellation is set (RAComputation); any thread
+ (nullable NSArray<RAClimbGroup *> *)groupsOfRides:(NSArray<RARide *> *)rides cancellation:(nullable RACancellation *)cancellation;
/// the passage of a climb of a ride, its rank by time (1: best) among the group's passages; 0 without time
- (NSUInteger)rankOfPassage:(RAClimbPassage *)passage;
@end

NS_ASSUME_NONNULL_END
