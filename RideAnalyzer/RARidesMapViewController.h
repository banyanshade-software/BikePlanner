//
//  RARidesMapViewController.h
//  RideAnalyzer
//
//  The Map tab beside the list (#82, R10): the tracks of the selected rides (two or more) or of the list, on one
//  map; the roads ridden most often stand out (RAHeatmap: color and width by the number of rides). Zoomed on all
//  the tracks when the rides change (Show All goes back to it); zoom and pan with the mouse and the trackpad.
//  Uses the tracks kept in the stats of the rides, computing in the background those of older rides. Built in code.
//

#import <Cocoa/Cocoa.h>
#import <MapKit/MapKit.h>

@class RALibraryDocument, RARide, RAHeatmap;

NS_ASSUME_NONNULL_BEGIN

@interface RARidesMapViewController : NSViewController

@property (weak, nonatomic, nullable) RALibraryDocument *library;
/// the rides to draw; selected: they are the selection of the list, for the status line
- (void)showRides:(NSArray<RARide *> *)rides selected:(BOOL)selected;
/// zooms on all the tracks
- (IBAction)showAll:(nullable id)sender;

// for tests
@property (readonly, nonatomic) MKMapView *mapView;
@property (readonly, nonatomic, nullable) RAHeatmap *heatmap;
@property (readonly, nonatomic) NSTextField *status;
/// the heatmap is being computed
@property (readonly, nonatomic, getter=isComputing) BOOL computing;
/// computes now, even when the tab does not show (tests)
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
