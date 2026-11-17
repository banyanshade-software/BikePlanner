//
//  BPPreferences.h
//  BikePlanner
//
//  User settings (Preferences window, #27), stored in NSUserDefaults under the keys read by BPEnvironment
//  (so the launch-argument overrides of the tests keep working).
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "BPEnvironment.h"
#import "BPColorScheme.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const BPDefaultPositionKey;   // "lat,lon"
extern NSString *const BPInitialRadiusKmKey;   // km
extern NSString *const BPStartPositionKey;     // BPStartPosition
extern NSString *const BPSightCategoriesKey;   // array of BPSights categories (#81)
extern NSString *const BPPOISearchRadiusKey;   // meters (#81), read by +[BPEnvironment poiSearchRadius]
extern NSString *const BPSightSearchRadiusKey; // meters (#81), read by +[BPEnvironment sightSearchRadius]
/// posted when a search distance changes: the open documents fetch their POIs again (#81)
extern NSNotificationName const BPPOISearchDidChangeNotification;

@interface BPPreferences : NSObject

+ (instancetype)shared;                                    // standard user defaults
- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults;

/// registers the default values (registration domain of the standard user defaults); called at launch
+ (void)registerDefaults;

/// used when the location is unknown, and as initial map center
@property (nonatomic) CLLocationCoordinate2D defaultPosition;
/// radius of the initial region around the start position
@property (nonatomic) double initialRadiusKm;
/// where a new document starts (#65)
@property (nonatomic) BPStartPosition startPosition;
/// colors of the route on the map (#71); setting a new one posts BPColorSchemeDidChangeNotification
@property (nonatomic) BPColorScheme *colorScheme;
/// sight categories of new documents (#81; default Culture, Viewpoints)
@property (nonatomic, copy) NSArray<NSString *> *defaultSightCategories;
/// search distances along the route, meters (#81): utilities (default 1500), sights (default 1000); global
@property (nonatomic) NSInteger poiSearchRadius;
@property (nonatomic) NSInteger sightSearchRadius;

@end

NS_ASSUME_NONNULL_END
