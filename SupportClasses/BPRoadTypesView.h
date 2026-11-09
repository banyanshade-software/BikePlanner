//
//  BPRoadTypesView.h
//  BikePlanner
//
//  Distance by road type and surface of the Info section (#53), one row per class with a small radio button: the
//  selected class is highlighted on the map (#66, was a hover on a text, #54). A "None" row turns the highlight off.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface BPRoadTypesView : NSView

/// BrouterInfo.roadTypesRows (bound to it): the selection is kept when its kind is still there, else back to None
@property (nonatomic, copy, nullable) NSArray<NSDictionary<NSString *, NSString *> *> *rows;
/// kind of the selected row ("road:track", BPRoadTypeKindKey), nil: None
@property (nonatomic, readonly, nullable) NSString *selectedKind;
/// called when the selection changes (by a click, or because the selected kind is no longer in the rows)
@property (copy, nullable) void (^selectionHandler)(NSString * _Nullable kind);

/// selects this kind (nil or a kind not in the rows: None), as a click on its radio button
- (void)selectKind:(nullable NSString *)kind;
/// the radio button of a kind (accessibility identifier "roadType.<kind>"), of None ("roadType.none") for nil
- (nullable NSButton *)radioForKind:(nullable NSString *)kind;

@end

NS_ASSUME_NONNULL_END
