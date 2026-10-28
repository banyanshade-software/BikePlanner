//
//  PlannerWindowController.h
//  BikePlanner
//
//  Created by Daniel on 15/08/2025.
//

#import <Cocoa/Cocoa.h>

@class BRFProfileEditor;

NS_ASSUME_NONNULL_BEGIN

@interface PlannerWindowController : NSWindowController
@property (strong, nonatomic) BRFProfileEditor *brfEditor;

// the document's plan was replaced (Revert to Saved): shows its BRouter parameters in the Params tab
- (void)planReplaced;

@end

NS_ASSUME_NONNULL_END
