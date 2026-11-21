//
//  RAAppDelegate.h
//  RideAnalyzer
//
//  Second app of the BikePlanner repository (#82): fetches the rides done and analyses them
//  (doc/05-ride-analyzer-spec.md, branch ride_analyzer). Document-based: a document is a ride library (R15).
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface RAAppDelegate : NSObject <NSApplicationDelegate>

/// the main menu, built in code (no XIB)
+ (NSMenu *)mainMenu;

@end

NS_ASSUME_NONNULL_END
