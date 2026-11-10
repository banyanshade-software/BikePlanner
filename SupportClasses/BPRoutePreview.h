//
//  BPRoutePreview.h
//  BikePlanner
//
//  Quick Look preview of a BikePlanner document or a GPX file (#70): what the file holds (route cut in stages,
//  reference trace, length, ascent, number of POIs) and its drawing, a summary band above the route on a map. Used
//  by the Quick Look extension (BikePlannerQuickLook), compiled in the app for the tests. Nothing here touches the
//  network except the optional Apple Maps snapshot.
//

#import <Cocoa/Cocoa.h>
#import <MapKit/MapKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BPRoutePreview : NSObject

/// a .bikeplan (BikePlan archive) or, for any other extension, a GPX file
+ (nullable instancetype)previewOfFileAtURL:(NSURL *)url error:(NSError * _Nullable *)error;
+ (nullable instancetype)previewOfBikePlanData:(NSData *)data name:(NSString *)name error:(NSError * _Nullable *)error;
+ (nullable instancetype)previewOfGPXData:(NSData *)data name:(NSString *)name error:(NSError * _Nullable *)error;

@property (readonly) NSString *name;
/// the route, one part per stage (#31); a GPX: its trace
@property (readonly) NSArray<NSArray<CLLocation *> *> *stages;
/// waypoints of a document without a computed route (drawn instead of the route), else empty
@property (readonly) NSArray<CLLocation *> *waypoints;
@property (readonly) NSArray<CLLocation *> *referenceTrace;
/// custom and fetched POIs (not the excluded ones), GPX <wpt>: counted in the summary, not drawn
@property (readonly) NSArray<CLLocation *> *pois;
@property (readonly) double length;     // m, 0: no route
@property (readonly) double ascent;     // m, < 0: unknown (no elevation)
@property (readonly) NSTimeInterval duration; // riding time estimated by BRouter, 0: unknown
/// "84.2 km · ↑ 1250 m · 3 h 10 · 2 stages · 12 POIs"
@property (readonly) NSString *summary;

/// what the map shows: all the points with a margin, the aspect ratio of `area`; MKMapRectNull without points
- (MKMapRect)mapRectForArea:(NSSize)area;
/// where the map is drawn in a preview of that size (below the summary band)
- (NSRect)mapAreaForSize:(NSSize)size;
- (NSPoint)pointForCoordinate:(CLLocationCoordinate2D)coordinate inMapArea:(NSRect)area;

/// Apple Maps background of the map area (main queue); nil without points, on error or after the timeout
- (void)takeMapSnapshotForSize:(NSSize)size timeout:(NSTimeInterval)timeout
                    completion:(void (^)(NSImage * _Nullable mapImage))completion;
/// draws the preview in the current graphics context (not flipped); no map image: a plain background
- (void)drawInRect:(NSRect)rect mapImage:(nullable NSImage *)mapImage;
- (NSBitmapImageRep *)bitmapOfSize:(NSSize)size mapImage:(nullable NSImage *)mapImage;

@end

NS_ASSUME_NONNULL_END
