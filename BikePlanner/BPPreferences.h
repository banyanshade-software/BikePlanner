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

@end

NS_ASSUME_NONNULL_END
