//
//  AppDelegate.h
//  BikePlanner
//
//  Created by Daniel on 09/08/2025.
//

#import <Cocoa/Cocoa.h>
#import "MapController.h"


@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (strong) IBOutlet NSWindow *window;
@property (weak) IBOutlet WKWebView *webView;
@property (weak) IBOutlet MapController *mapController;


@end

