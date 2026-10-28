//
//  BPPreferences.h
//  BikePlanner
//
//  User settings (Preferences window, #27), stored in NSUserDefaults under the keys read by BPEnvironment
//  (so the launch-argument overrides of the tests keep working).
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const BPDefaultPositionKey;   // "lat,lon"
extern NSString *const BPInitialRadiusKmKey;   // km

@interface BPPreferences : NSObject

+ (instancetype)shared;                                    // standard user defaults
- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults;

/// registers the default values (registration domain of the standard user defaults); called at launch
+ (void)registerDefaults;

/// used when the location is unknown, and as initial map center
@property (nonatomic) CLLocationCoordinate2D defaultPosition;
/// radius of the initial region around the start position
@property (nonatomic) double initialRadiusKm;

@end

NS_ASSUME_NONNULL_END
