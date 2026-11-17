//
//  BPPOICache.h
//  BikePlanner
//
//  Cache of the Overpass answers per area (#84): the elements (as Overpass returns them) of cells of 0.02°
//  (~2.2 × 1.5 km), one layer per kind of POI ("utilities": water, toilets, repair stations, cemeteries; one per sight
//  category, #81). A cell of a layer is complete: a new route asks only for the cells it lacks, then keeps the POIs
//  within the search distances. Kept 7 days, in memory and on disk (Caches of the app; a temporary folder in the unit
//  test host), the oldest cells evicted above the size limit. No UI (also in the Quick Look extension).
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "BPOverpassServers.h"

NS_ASSUME_NONNULL_BEGIN

/// size of a cell, degrees
extern const double BPPOICellSize;
/// layer of the utilities (the others: the sight categories)
extern NSString *const BPPOIUtilitiesLayer;

typedef struct {
    NSInteger lat, lon;   // floor(degrees / BPPOICellSize)
} BPPOICell;

@interface BPPOICache : NSObject

/// directory: BPEnvironment (+poiCacheDirectory)
+ (instancetype)shared;
/// nil: memory only
- (instancetype)initWithDirectory:(nullable NSURL *)directory;

@property (copy, nonatomic) NSDate *(^clock)(void);
@property (nonatomic) NSTimeInterval maxAge;   // 7 days
@property (nonatomic) NSUInteger maxBytes;     // 50 MB on disk

/// the elements of a cell for a layer; nil: not cached or expired
- (nullable NSArray<NSDictionary *> *)elementsForCell:(BPPOICell)cell layer:(NSString *)layer;
- (void)setElements:(NSArray<NSDictionary *> *)elements forCell:(BPPOICell)cell layer:(NSString *)layer;
- (void)removeAll;
- (NSUInteger)diskSize;

+ (BPPOICell)cellOfLatitude:(double)latitude longitude:(double)longitude;
+ (BPGeoBox)boxOfCell:(BPPOICell)cell;
/// the cells (NSValue of BPPOICell) within `radius` meters of the route, without duplicates, from the start
+ (NSArray<NSValue *> *)cellsAlongRoute:(NSArray<CLLocation *> *)route radius:(double)radius;

@end

NS_ASSUME_NONNULL_END
