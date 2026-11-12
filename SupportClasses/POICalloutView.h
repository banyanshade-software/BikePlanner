//
//  POICalloutView.h
//  BikePlanner
//
//  Created by Daniel Braun on 20/08/2025.
//
//  Detail view of the POI callout (#72): position on the route, useful tags, all OSM tags (collapsed), web addresses
//  as links, buttons OpenStreetMap / Street View / Copy, "Include in track" (#5), Edit… (custom POIs). MapKit shows the title (type)
//  and the subtitle (name) above it.
//

#import <Cocoa/Cocoa.h>
#import <MapKit/MapKit.h>
NS_ASSUME_NONNULL_BEGIN

@class BPPOIDescription;

/// actions of the callout controls (MapController); the sender is the control
@protocol POICalloutActions <NSObject>
- (void) openPOIInOSM:(NSButton *)sender;
- (void) streetViewAtPOI:(NSButton *)sender;
- (void) copyPOICoordinates:(NSButton *)sender;
- (void) editPOIFromCallout:(NSButton *)sender;
- (void) includeCheckboxChanged:(NSButton *)sender;
@end

@interface POICalloutView : NSView

@property (strong,nonatomic) NSDictionary *infodic;
/// target of the controls; set before the content is built (first fill, #78)
@property (weak,nonatomic) id<POICalloutActions> actionTarget;
/// the state of the checkbox (it may not be built yet)
@property (nonatomic) BOOL included;
/// checked: the POI is exported with the track (#5); unchecked: excluded. The controls build the content (#78)
@property (readonly,nonatomic) NSButton *includeCheckbox;
@property (readonly,nonatomic) NSButton *osmButton;
@property (readonly,nonatomic) NSButton *streetViewButton;
@property (readonly,nonatomic) NSButton *coordinatesButton;
@property (readonly,nonatomic) NSButton *editButton;        // custom POIs only
@property (weak,nonatomic) MKAnnotationView *annotview;

/// fills the view; position: "km 12.4 · 180 m off route", nil without route
- (void) configureWithDescription:(BPPOIDescription *)description position:(nullable NSString *)position;
/// the text shown (tests)
@property (readonly,nonatomic) NSString *displayedText;
/// links shown, in order (tests)
@property (readonly,nonatomic) NSArray<NSURL *> *displayedLinks;
/// "All OSM tags" expanded
@property (nonatomic) BOOL showsAllTags;

@end

NS_ASSUME_NONNULL_END
