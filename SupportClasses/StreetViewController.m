//
//  StreetViewController.m
//  BikePlanner
//
//  Created by Daniel on 10/08/2025.
//

#import "StreetViewController.h"
#import "BPEnvironment.h"
#import "BPSecrets.h"

// Street View pane (#49): with a Google Maps key (Secret.h), the Maps Embed API in an iframe of a local page — the
// supported way to embed Street View, with a small address chip only; without a key, the Google Maps web app (and
// its large info box over the panorama).

// origin of the local page, i.e. the HTTP referrer seen by Google: the key can be restricted to it.
// A reserved domain (RFC 2606): never resolved, nothing is loaded from it.
static NSString *const kEmbedPageBaseURL = @"https://bikeplanner.invalid/";

@interface StreetViewController ()
// nil: the key of Secret.h; set by tests
@property (nonatomic, copy, nullable) NSString *apiKey;
@end

@implementation StreetViewController

+ (NSURL *)embedURLForCoord:(CLLocationCoordinate2D)coord heading:(double)heading key:(NSString *)key
{
    heading = fmod(heading, 360);
    if (heading < 0) heading += 360;
    // only unreserved characters are left as is in the key ('+' would be read as a space)
    NSCharacterSet *unreserved = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *k = [key stringByAddingPercentEncodingWithAllowedCharacters:unreserved] ?: @"";
    NSString *s = [NSString stringWithFormat:
        @"https://www.google.com/maps/embed/v1/streetview?key=%@&location=%f,%f&heading=%.2f&pitch=0&fov=90",
        k, coord.latitude, coord.longitude, heading];
    return [NSURL URLWithString:s];
}

+ (NSString *)embedHTMLForURL:(NSURL *)url
{
    NSString *src = [url.absoluteString stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    return [NSString stringWithFormat:
        @"<!DOCTYPE html><html><head><meta charset=\"utf-8\">"
        "<style>html,body{margin:0;padding:0;width:100%%;height:100%%;overflow:hidden;background:#000}"
        "iframe{display:block;border:0;width:100%%;height:100%%}</style></head>"
        "<body><iframe src=\"%@\" allowfullscreen></iframe></body></html>", src];
}

- (NSString *)effectiveAPIKey
{
    return self.apiKey ?: [BPSecrets googleMapsAPIKey];
}

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
    NSString *key = [self effectiveAPIKey];
    if (key.length) {
        NSURL *embed = [StreetViewController embedURLForCoord:coord heading:bearing key:key];
        [self.webView loadHTMLString:[StreetViewController embedHTMLForURL:embed]
                             baseURL:[NSURL URLWithString:kEmbedPageBaseURL]];
        return;
    }
    NSString *surl = [NSString stringWithFormat:@"https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=%f,%f&heading=%f",
    coord.latitude, coord.longitude, bearing];
    NSURL *url = [NSURL URLWithString:surl];
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:req];
    
}



@end
