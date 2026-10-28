//
//  PlannerWindowController.m
//  BikePlanner
//
//  Created by Daniel on 15/08/2025.
//

#import "PlannerWindowController.h"
#import "Document.h"
#import "MapController.h"
#import "BRFProfileEditor.h"

@interface PlannerWindowController ()

@end

@implementation PlannerWindowController

- (void)windowDidLoad
{
    [super windowDidLoad];
    Document *d = (Document *)self.document;
    NSAssert(d, @"nil document");
    NSAssert([d isKindOfClass:[Document class]], @"bad class document");
    NSAssert(d.mapController, @"document no mapctrl");
    NSAssert(d.mapController.svCtrl, @"document no svctrl");
    NSAssert(d.mapController.document, @"document not linked to mapController");
    NSAssert(d==d.mapController.document, @"wrong document  linked to mapController");
    [d.mapController initializeMapview];
    [d.mapController.svCtrl initializeStreetView];
    
    [d.mapController fullRefresh:YES];
    [self setupBrfEditor];
    [self.window makeKeyAndOrderFront:nil];
}


- (void) setupBrfEditor
{
    Document *d = (Document *)self.document;
    self.brfEditor = [[BRFProfileEditor alloc] initWithNibName:@"BRFProfileEditor" bundle:nil]; //initWithProfileName:@"trekking"];
    [_brfEditor loadProfileName:@"trekking"];
    
    // overrides are sent as profile:<name>=<value> parameters by BRouterClient (#15, #35); none = profile defaults
    _brfEditor.completionHandler = ^(NSDictionary<NSString *, NSString *> *overrideParams) {
        NSLog(@"User overrides: %@", overrideParams);
        NSDictionary *old = d.mapController.profileOverrides ?: @{};
        if ([old isEqualToDictionary:overrideParams ?: @{}]) return;
        d.mapController.profileOverrides = overrideParams ?: @{};
        [d.mapController shouldRecalcRoute];
    };
    
    _brfEditor.view.frame = d.brfParamsPlaceholder.bounds;
    _brfEditor.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Add as child view controller
    //[self addChildViewController:vc];

    // Add its view into the container
    [d.brfParamsPlaceholder addSubview:_brfEditor.view];

    //[_brfEditor showWindow:self];

}
@end
