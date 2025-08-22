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
@property (strong,nonatomic) BikePlan *plan;
@property (strong, nonatomic) BRFProfileEditor *brfEditor;
@end

