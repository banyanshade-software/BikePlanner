//
//  BPSightsView.h
//  BikePlanner
//
//  Sights near the route in the Info section (#81): the categories to fetch (a pull-down menu with checkable items),
//  the distance under which a sight is included in the track, and the list of the sights along the route (km, name,
//  type, distance from the route, "in track" checkbox). It only shows and reports: the window controller applies the
//  changes (undoable) and gives the rows back.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// keys of a row
extern NSString *const BPSightRowKey;       // poiKey
extern NSString *const BPSightRowAlong;     // NSNumber, meters from the start
extern NSString *const BPSightRowOff;       // NSNumber, meters from the route
extern NSString *const BPSightRowName;
extern NSString *const BPSightRowType;      // localized type name
extern NSString *const BPSightRowIncluded;  // NSNumber BOOL

@interface BPSightsView : NSView

@property (copy, nonatomic) NSArray<NSString *> *categories;
/// meters, 0: none
@property (nonatomic) NSInteger includeDistance;
@property (copy, nonatomic) NSArray<NSDictionary<NSString *, id> *> *rows;

@property (copy, nullable) void (^categoriesHandler)(NSArray<NSString *> *categories);
@property (copy, nullable) void (^includeDistanceHandler)(NSInteger meters);
@property (copy, nullable) void (^inclusionHandler)(NSString *poiKey, BOOL included);
@property (copy, nullable) void (^selectionHandler)(NSString *poiKey);

@property (readonly, nonatomic) NSPopUpButton *categoriesMenu;   // accessibility identifier sightCategories
@property (readonly, nonatomic) NSPopUpButton *distanceMenu;     // sightIncludeDistance
/// fills a pull-down menu: the summary of the categories as title, one checkable item per category (representedObject:
/// the category) sending action to target (also used by the Preferences)
+ (void)fillCategoriesMenu:(NSPopUpButton *)popup categories:(NSArray<NSString *> *)categories target:(id)target action:(SEL)action;
/// the list (#81: a table, rows made when visible)
@property (readonly, nonatomic) NSTableView *tableView;
/// the "In track" checkbox of a sight (made if needed); a row selected as by a click (tests)
- (nullable NSButton *)includeCheckboxForKey:(NSString *)key;
- (void)selectRowWithKey:(NSString *)key;
/// the distances of the "Include within" menu (meters; 0: none)
+ (NSArray<NSNumber *> *)includeDistances;
/// "12.4", "1.1 km" / "80 m"
+ (NSString *)kilometersText:(double)meters;
+ (NSString *)distanceText:(double)meters;

@end

NS_ASSUME_NONNULL_END
