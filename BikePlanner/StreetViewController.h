//
//  StreetViewController.h
//  BikePlanner
//
//  Created by Daniel on 10/08/2025.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface StreetViewController : NSObject
@property (weak) IBOutlet WKWebView *webView;

- (void) initializeStreetView;
@end

NS_ASSUME_NONNULL_END
