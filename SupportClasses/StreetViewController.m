//
//  StreetViewController.m
//  BikePlanner
//
//  Created by Daniel on 10/08/2025.
//

#import "StreetViewController.h"
#import "BPEnvironment.h"

@implementation StreetViewController

// first page: the panorama at the default position (was a hard-coded Google Maps URL, #18)
- (void) initializeStreetView
{
    if ([BPEnvironment streetViewDisabled]) return;
    [self viewCoord:[BPEnvironment defaultPosition] lookingAt:0 coalesce:NO];
}


- (void) viewCoord:(CLLocationCoordinate2D)coord  lookingAt:(double)bearing coalesce:(BOOL)coal
{
    if ((0)) return; // disable
    if ([BPEnvironment streetViewDisabled]) return;
    if ((0)) bearing-=20;
    NSString *surl = [NSString stringWithFormat:@"https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=%f,%f&heading=%f",
    coord.latitude, coord.longitude, bearing];
    NSURL *url = [NSURL URLWithString:surl];
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:req];
    
}



@end
