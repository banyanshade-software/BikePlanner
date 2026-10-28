//
//  BPPlaceSearch.h
//  BikePlanner
//
//  Apple place search (MKLocalSearch), shared by the toolbar search field (#40) and the Preferences (#27).
//  Tests replace the search with +setSearchHandlerForTesting: (everything runs offline).
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^BPPlaceSearchCompletion)(NSArray<MKMapItem *> *items, NSError * _Nullable error);
typedef void (^BPPlaceSearchHandler)(NSString *query, MKCoordinateRegion region, BPPlaceSearchCompletion completion);

@interface BPPlaceSearch : NSObject

/// Searches places near region; completion on the main queue (items empty when nothing is found).
+ (void)search:(NSString *)query near:(MKCoordinateRegion)region completion:(BPPlaceSearchCompletion)completion;

/// "Locality, administrative area, country" of a result (for lists of candidates)
+ (NSString *)subtitleForItem:(MKMapItem *)item;
/// "Name — locality, …" (menu item title)
+ (NSString *)titleForItem:(MKMapItem *)item;

/// Region to show a result: a few km for a place, ~20 km for a locality/region without street
+ (MKCoordinateRegion)regionForItem:(MKMapItem *)item;

+ (void)setSearchHandlerForTesting:(nullable BPPlaceSearchHandler)handler;

@end

NS_ASSUME_NONNULL_END
