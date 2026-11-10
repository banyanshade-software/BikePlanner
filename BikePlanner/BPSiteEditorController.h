//
//  BPSiteEditorController.h
//  BikePlanner
//
//  Start sites editor (#67): a developer tool to edit RemarkableSites.plist (#65) in the app — add a site where the
//  map is, set its position, kind and Street View heading (live preview), reorder, remove, export the plist to the
//  source tree. Not in the delivered app: compiled only with BP_SITE_EDITOR=1 (scripts/build_site_editor.sh), menu
//  Develop ▸ Start Sites Editor…; scripts/make_dmg.sh refuses an app that contains it.
//

#if BP_SITE_EDITOR

#import <Cocoa/Cocoa.h>
#import <CoreLocation/CoreLocation.h>
#import "BPRemarkableSites.h"

NS_ASSUME_NONNULL_BEGIN

/// what the editor acts on: the map and Street View of the front document window
@protocol BPSiteEditorTarget <NSObject>
@property (readonly) CLLocationCoordinate2D mapCenter;
- (void)showSite:(BPRemarkableSite *)site;
- (void)previewStreetViewAt:(CLLocationCoordinate2D)coordinate heading:(double)heading;
@end

@interface BPSiteEditorController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>

/// adds Develop ▸ Start Sites Editor… to the main menu
+ (void)installMenu;
+ (instancetype)shared;

/// entries in the format of RemarkableSites.plist (name, latitude, longitude, kind, heading), header comment kept
- (instancetype)initWithPropertyListData:(nullable NSData *)data;
@property (readonly) NSArray<NSDictionary *> *entries;
@property (readonly) BOOL edited;
/// default: the map controller of the main window's document; set by tests
@property (copy) id<BPSiteEditorTarget> _Nullable (^targetProvider)(void);
/// selected row, -1: none
@property (nonatomic) NSInteger selectedIndex;
/// what would make the tests fail or the list wrong (empty or duplicate name, outside metropolitan France, first
/// site not Mont Ventoux); empty when all is well
@property (readonly) NSArray<NSString *> *problems;
/// RemarkableSites.plist with the edited entries
- (nullable NSData *)exportData;

- (IBAction)goToSite:(id)sender;
- (IBAction)addSiteHere:(id)sender;
- (IBAction)setPositionHere:(id)sender;
- (IBAction)removeSite:(id)sender;
- (IBAction)moveSiteUp:(id)sender;
- (IBAction)moveSiteDown:(id)sender;
- (IBAction)revertSites:(id)sender;
- (IBAction)exportSites:(id)sender;

// edit fields of the selected site (accessibility identifiers siteName, siteKind, siteLatitude, siteLongitude,
// siteHeading, siteHeadingSlider)
@property (readonly) NSTextField *nameField;
@property (readonly) NSPopUpButton *kindPopUp;
@property (readonly) NSTextField *latitudeField;
@property (readonly) NSTextField *longitudeField;
@property (readonly) NSTextField *headingField;
@property (readonly) NSSlider *headingSlider;
@property (readonly) NSTextField *statusLabel;
- (nullable NSButton *)buttonWithIdentifier:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END

#endif
