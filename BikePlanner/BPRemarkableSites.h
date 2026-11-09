//
//  BPRemarkableSites.h
//  BikePlanner
//
//  Remarkable sites in France (famous climbs, monuments, natural sites) where a new document can start, picked
//  at random (Preferences ▸ Start position, #65).
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BPSiteKind) {
    BPSiteKindClimb,
    BPSiteKindMonument,
    BPSiteKindNature,
};

@interface BPRemarkableSite : NSObject
@property (readonly) NSString *name;
@property (readonly) CLLocationCoordinate2D coordinate;
@property (readonly) BPSiteKind kind;
/// "Mont Ventoux — famous climb", for the map message
@property (readonly) NSString *displayText;
@end

@interface BPRemarkableSites : NSObject
+ (NSArray<BPRemarkableSite *> *) sites;
/// a site at random; the test hook BPRemarkableSiteIndex (BPEnvironment) chooses it
+ (BPRemarkableSite *) randomSite;
@end

NS_ASSUME_NONNULL_END
