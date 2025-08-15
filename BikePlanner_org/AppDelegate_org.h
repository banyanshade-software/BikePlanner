//
//  AppDelegate.h
//  BikePlanner
//
//  Created by Daniel on 09/08/2025.
//

#import <Cocoa/Cocoa.h>
#import "MapController.h"
#import "StreetViewController.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (strong) IBOutlet NSWindow *window;
@property (weak) IBOutlet MapController *mapController;
@property (weak) IBOutlet StreetViewController *streetViewController;


@end

