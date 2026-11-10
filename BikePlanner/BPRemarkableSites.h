//
//  BPRemarkableSites.h
//  BikePlanner
//
//  Remarkable sites in France (famous climbs, monuments, natural sites) where a new document can start, picked
//  at random (Preferences ▸ Start position, #65). The list is the resource RemarkableSites.plist.
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
/// direction of the Street View camera, degrees (0 = north, 90 = east)
@property (readonly) double heading;
/// "Mont Ventoux — famous climb", for the map message
@property (readonly) NSString *displayText;
@end

@interface BPRemarkableSites : NSObject
/// the sites of RemarkableSites.plist
+ (NSArray<BPRemarkableSite *> *) sites;
/// sites of a property list (format: RemarkableSites.plist); invalid entries are skipped
+ (NSArray<BPRemarkableSite *> *) sitesFromPropertyList:(nullable id)plist;
/// a site at random, nil if the list is empty; the test hook BPRemarkableSiteIndex (BPEnvironment) chooses it
+ (nullable BPRemarkableSite *) randomSite;

// for the start sites editor (#67, built on demand) and its tests
/// RemarkableSites.plist of the app bundle, as is
+ (nullable NSData *) bundledPropertyListData;
/// the first XML comment of a property list file (the header of RemarkableSites.plist), nil if none
+ (nullable NSString *) headerCommentOfPropertyListData:(NSData *)data;
/// XML property list of these entries (format of RemarkableSites.plist; whole headings as integers), with this
/// comment after the DOCTYPE line
+ (nullable NSData *) propertyListDataForEntries:(NSArray<NSDictionary *> *)entries headerComment:(nullable NSString *)comment;
/// the bounding box of metropolitan France (with Corsica), the area where the sites must be (checked by a test)
+ (BOOL) isInMetropolitanFrance:(CLLocationCoordinate2D)c;
@end

NS_ASSUME_NONNULL_END
