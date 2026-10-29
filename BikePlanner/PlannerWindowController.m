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

// document view of the Info scroll view: content from the top
@interface BPInfoDocumentView : NSView
@end
@implementation BPInfoDocumentView
- (BOOL)isFlipped { return YES; }
@end

@implementation PlannerWindowController

- (nullable NSTabView *) tabViewIn:(NSView *)root
{
    if ([root isKindOfClass:[NSTabView class]]) return (NSTabView *)root;
    for (NSView *v in root.subviews) {
        NSTabView *t = [self tabViewIn:v];
        if (t) return t;
    }
    return nil;
}

// Info section (#53): its content (box of Document.xib) goes into a scroll view, with the distance by road type
// below (label bound to plan.brouterInfo.roadTypesAttributedText). Built here so that Document.xib is unchanged.
- (void) setupInfoSection
{
    Document *d = (Document *)self.document;
    NSTabView *tabs = [self tabViewIn:self.window.contentView]; // (a hidden tab's view is not in the hierarchy)
    NSSplitView *split = (NSSplitView *)tabs.superview.superview;   // Info | Street View / Params tabs (#43)
    if (![split isKindOfClass:[NSSplitView class]] || split.subviews.count < 2) return;
    NSView *infoPane = split.subviews[0];
    NSArray<NSView *> *content = [infoPane.subviews copy];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:infoPane.bounds];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;
    NSView *doc = [[BPInfoDocumentView alloc] init];
    doc.translatesAutoresizingMaskIntoConstraints = NO;
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *c in content) {
        NSSize size = c.frame.size;
        [c removeFromSuperview];
        c.translatesAutoresizingMaskIntoConstraints = NO;
        [c.widthAnchor constraintEqualToConstant:size.width].active = YES;
        [c.heightAnchor constraintEqualToConstant:size.height].active = YES;
        [stack addArrangedSubview:c];
    }
    NSTextField *roads = [NSTextField wrappingLabelWithString:@""];
    roads.accessibilityIdentifier = @"routeRoadTypes";
    [roads bind:NSValueBinding toObject:d withKeyPath:@"plan.brouterInfo.roadTypesAttributedText" options:nil];
    [stack addArrangedSubview:roads];
    [stack setCustomSpacing:2 afterView:stack.arrangedSubviews.firstObject];
    [doc addSubview:stack];
    scroll.documentView = doc;
    [infoPane addSubview:scroll];
    NSClipView *clip = scroll.contentView;
    [NSLayoutConstraint activateConstraints:@[
        [doc.leadingAnchor constraintEqualToAnchor:clip.leadingAnchor],
        [doc.trailingAnchor constraintEqualToAnchor:clip.trailingAnchor],
        [doc.topAnchor constraintEqualToAnchor:clip.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:doc.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:doc.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:doc.bottomAnchor constant:-8],
        [roads.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:12],
        [roads.widthAnchor constraintEqualToConstant:240],
    ]];
}

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
    [self setupInfoSection];
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
