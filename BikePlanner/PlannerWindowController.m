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
#import "BikePlan.h"

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
    [_brfEditor loadProfileName:d.plan.profileName];
    _brfEditor.appliedOverrides = d.plan.profileOverrides; // saved in the document (#44)
    
    // overrides are sent as profile:<name>=<value> parameters by BRouterClient (#15, #35); none = profile defaults
    __weak PlannerWindowController *weakSelf = self;
    _brfEditor.completionHandler = ^(NSDictionary<NSString *, NSString *> *overrideParams) {
        NSLog(@"User overrides: %@", overrideParams);
        [weakSelf setProfileOverrides:overrideParams];
    };
    
    _brfEditor.view.frame = d.brfParamsPlaceholder.bounds;
    _brfEditor.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Add as child view controller
    //[self addChildViewController:vc];

    // Add its view into the container
    [d.brfParamsPlaceholder addSubview:_brfEditor.view];

    //[_brfEditor showWindow:self];

}
// undoable, recomputes the route (#44)
- (void)setProfileOverrides:(NSDictionary<NSString *, NSString *> *)overrides
{
    Document *d = (Document *)self.document;
    NSDictionary *old = d.plan.profileOverrides;
    if ([old isEqualToDictionary:overrides ?: @{}]) return;
    [d.undoManager registerUndoWithTarget:self handler:^(PlannerWindowController *target) {
        [target setProfileOverrides:old];
    }];
    [d.undoManager setActionName:NSLocalizedString(@"change routing parameters", @"undo action")];
    d.plan.profileOverrides = overrides;
    _brfEditor.appliedOverrides = d.plan.profileOverrides;
    [d.mapController shouldRecalcRoute];
}

- (void)planReplaced
{
    _brfEditor.appliedOverrides = ((Document *)self.document).plan.profileOverrides;
}

@end
