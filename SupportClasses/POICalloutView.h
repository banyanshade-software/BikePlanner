//
//  POICalloutView.h
//  BikePlanner
//
//  Created by Daniel Braun on 20/08/2025.
//
//  Detail view of the POI callout (#72): position on the route, useful tags, all OSM tags (collapsed), buttons
//  OpenStreetMap / Street View / Copy, Include / Exclude (#5), Edit… (custom POIs). MapKit shows the title (type)
//  and the subtitle (name) above it.
//

#import <Cocoa/Cocoa.h>
#import <MapKit/MapKit.h>
NS_ASSUME_NONNULL_BEGIN

@class BPPOIDescription;

@interface POICalloutView : NSView

@property (strong,nonatomic) NSDictionary *infodic;
@property (readonly,nonatomic) NSSegmentedControl *excludeControl;
// targets and actions are set by MapController
@property (readonly,nonatomic) NSButton *osmButton;
@property (readonly,nonatomic) NSButton *streetViewButton;
@property (readonly,nonatomic) NSButton *coordinatesButton;
@property (readonly,nonatomic) NSButton *editButton;        // custom POIs only
@property (weak,nonatomic) MKAnnotationView *annotview;

/// fills the view; position: "km 12.4 · 180 m off route", nil without route
- (void) configureWithDescription:(BPPOIDescription *)description position:(nullable NSString *)position;
/// the text shown (tests)
@property (readonly,nonatomic) NSString *displayedText;
/// "All OSM tags" expanded
@property (nonatomic) BOOL showsAllTags;

@end

NS_ASSUME_NONNULL_END
