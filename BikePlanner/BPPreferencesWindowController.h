//
//  BPPreferencesWindowController.h
//  BikePlanner
//
//  Preferences window (BikePlanner ▸ Preferences…, ⌘,), built in code (#27). Changes apply immediately.
//

#import <Cocoa/Cocoa.h>
#import <MapKit/MapKit.h>
#import "BPPreferences.h"

NS_ASSUME_NONNULL_BEGIN

@interface BPPreferencesWindowController : NSWindowController

- (instancetype)initWithPreferences:(BPPreferences *)preferences;

@property (readonly) BPPreferences *preferences;

/// center of the map of the front document window; NO if there is none (default implementation; replaced by tests)
@property (copy) BOOL (^mapCenterProvider)(CLLocationCoordinate2D *center);
/// shows the menu of search candidates under the search field (default: pop-up menu; replaced by tests)
@property (copy) void (^presentResultsMenu)(NSMenu *menu, NSView *view);

@end

NS_ASSUME_NONNULL_END
