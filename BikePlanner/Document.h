//
//  Document.h
//  BikePlanner
//
//  Created by Daniel on 15/08/2025.
//

#import <Cocoa/Cocoa.h>

@class MapController;
@class BikePlan;
@class BRFProfileEditor;

@interface Document : NSDocument

@property (weak) IBOutlet MapController *mapController;
//@property (strong, nonatomic) BRFProfileEditor *brfEditor;
@property (weak, nonatomic) IBOutlet NSView *brfParamsPlaceholder;

@property (strong,nonatomic) BikePlan *plan;
@end

