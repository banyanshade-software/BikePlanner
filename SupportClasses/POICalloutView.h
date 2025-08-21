//
//  POICalloutView.h
//  BikePlanner
//
//  Created by Daniel Braun on 20/08/2025.
//

#import <Cocoa/Cocoa.h>
#import <MapKit/MapKit.h>
NS_ASSUME_NONNULL_BEGIN

@interface POICalloutView : NSView

@property (assign,nonatomic) NSDictionary *infodic;
@property  (readonly,nonatomic) NSSegmentedControl *excludeControl;
@property (weak,nonatomic) MKAnnotationView *annotview;
@end

NS_ASSUME_NONNULL_END
