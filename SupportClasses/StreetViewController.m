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
// The key is checked once (a request to the Embed API, with the referrer of the iframe) before it is used:
// accepted → the Embed API; rejected (HTTP 4xx) → the Google Maps web app until the app is relaunched; Google not
// reached (network error, 5xx) → the Google Maps web app for this view, checked again at the next one. Nothing is
// shown while the check runs; the last requested view is shown when it ends.

// origin of the local page, i.e. the HTTP referrer seen by Google: the key can be restricted to it.
// A reserved domain (RFC 2606): never resolved, nothing is loaded from it.
static NSString *const kEmbedPageBaseURL = @"https://bikeplanner.invalid/";

typedef NS_ENUM(NSInteger, BPEmbedKeyState) {
    BPEmbedKeyUnchecked,
    BPEmbedKeyChecking,
    BPEmbedKeyValid,
    BPEmbedKeyRejected,
};

@interface StreetViewController ()
// nil: the key of Secret.h; set by tests
@property (nonatomic, copy, nullable) NSString *apiKey;
@end

@implementation StreetViewController {
    BPEmbedKeyState _keyState;
    NSString *_checkedKey;              // the key _keyState is about
    BOOL _hasPending;                   // a view requested while the key is checked
    CLLocationCoordinate2D _pendingCoord;
    double _pendingBearing;
}

+ (NSURL *)embedURLForCoord:(CLLocationCoordinate2D)coord heading:(double)heading key:(NSString *)key
{
    heading = fmod(heading, 360);
    if (heading < 0) heading += 360;
    // only unreserved characters are left as is in the key ('+' would be read as a space)
    NSCharacterSet *unreserved = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *k = [key stringByAddingPercentEncodingWithAllowedCharacters:unreserved] ?: @"";
    NSString *s = [NSString stringWithFormat:@"streetview?key=%@&location=%f,%f&heading=%.2f&pitch=0&fov=90",
        k, coord.latitude, coord.longitude, heading];
    return [NSURL URLWithString:s relativeToURL:[BPEnvironment googleMapsEmbedURL]].absoluteURL;
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
    if (key.length && ![key isEqualToString:_checkedKey]) {
        _checkedKey = [key copy];
        _keyState = BPEmbedKeyUnchecked;
    }
    if (key.length && _keyState == BPEmbedKeyValid) {
        [self loadEmbedAt:coord heading:bearing key:key];
        return;
    }
    if (key.length && _keyState != BPEmbedKeyRejected) {
        _hasPending = YES;
        _pendingCoord = coord;
        _pendingBearing = bearing;
        if (_keyState == BPEmbedKeyUnchecked) [self checkKey:key at:coord];
        return;
    }
    [self loadMapsWebAppAt:coord heading:bearing];
}

- (void)loadEmbedAt:(CLLocationCoordinate2D)coord heading:(double)bearing key:(NSString *)key
{
    NSURL *embed = [StreetViewController embedURLForCoord:coord heading:bearing key:key];
    [self.webView loadHTMLString:[StreetViewController embedHTMLForURL:embed]
                         baseURL:[NSURL URLWithString:kEmbedPageBaseURL]];
}

- (void)loadMapsWebAppAt:(CLLocationCoordinate2D)coord heading:(double)bearing
{
    NSString *surl = [NSString stringWithFormat:@"https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=%f,%f&heading=%f",
    coord.latitude, coord.longitude, bearing];
    NSURL *url = [NSURL URLWithString:surl];
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:req];
}

// Google answers HTTP 403 with an error page for an invalid key, a key without the Maps Embed API or restricted to
// other websites (hence the Referer of the iframe)
- (void)checkKey:(NSString *)key at:(CLLocationCoordinate2D)coord
{
    _keyState = BPEmbedKeyChecking;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
        [StreetViewController embedURLForCoord:coord heading:0 key:key]];
    [req setValue:kEmbedPageBaseURL forHTTPHeaderField:@"Referer"];
    req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    req.timeoutInterval = 15;
    __weak StreetViewController *weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger status = [resp isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf keyChecked:key status:status];
        });
    }];
    [task resume];
}

- (void)keyChecked:(NSString *)key status:(NSInteger)status
{
    if (![key isEqualToString:_checkedKey] || _keyState != BPEmbedKeyChecking) return; // key changed meanwhile
    if (status == 200) {
        _keyState = BPEmbedKeyValid;
    } else if (status >= 400 && status < 500 && status != 429) {
        _keyState = BPEmbedKeyRejected;
        NSLog(@"Street View: Google Maps key rejected (HTTP %ld), using the Google Maps web app", (long)status);
    } else {
        _keyState = BPEmbedKeyUnchecked;
        NSLog(@"Street View: Google Maps key not checked (HTTP %ld), using the Google Maps web app", (long)status);
    }
    if (!_hasPending || [BPEnvironment streetViewDisabled]) return;
    _hasPending = NO;
    if (_keyState == BPEmbedKeyValid) {
        [self loadEmbedAt:_pendingCoord heading:_pendingBearing key:key];
    } else {
        [self loadMapsWebAppAt:_pendingCoord heading:_pendingBearing];
    }
}



@end
