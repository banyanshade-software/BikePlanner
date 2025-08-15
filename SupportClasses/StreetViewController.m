//
//  StreetViewController.m
//  BikePlanner
//
//  Created by Daniel on 10/08/2025.
//

#import "StreetViewController.h"

@implementation StreetViewController

- (void) initializeStreetView
{
    NSString *s = @"https://www.google.com/maps/@44.1042884,0.5239076,3a,75y,166.01h,82.2t/data=!3m7!1e1!3m5!1sUAywig97gsSiSgRpXM4R_g!2e0!6shttps:%2F%2Fstreetviewpixels-pa.googleapis.com%2Fv1%2Fthumbnail%3Fcb_client%3Dmaps_sv.tactile%26w%3D900%26h%3D600%26pitch%3D7.796108031354706%26panoid%3DUAywig97gsSiSgRpXM4R_g%26yaw%3D166.01471008172715!7i16384!8i8192?entry=ttu&g_ep=EgoyMDI1MDgwNi4wIKXMDSoASAFQAw%3D%3D";
    // https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=44.1042884,0.5239076
    // &heading 0-360
    NSURL *url = [NSURL URLWithString:s];
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:req];
    
    
}


- (void) viewCoord:(CLLocationCoordinate2D)coord  lookingAt:(double)bearing coalesce:(BOOL)coal
{
    if ((0)) return; // disable
    NSString *surl = [NSString stringWithFormat:@"https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=%f,%f&heading=%f",
    coord.latitude, coord.longitude, bearing];
    NSURL *url = [NSURL URLWithString:surl];
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:req];
    
}



@end
