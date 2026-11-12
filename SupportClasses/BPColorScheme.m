//
//  BPColorScheme.m
//  BikePlanner
//
//  Colors of the route on the map (#71).
//

#import "BPColorScheme.h"

NSString *const BPColorSchemeKey = @"BPColorScheme";
NSNotificationName const BPColorSchemeDidChangeNotification = @"BPColorSchemeDidChangeNotification";

static NSColor *BPRGB(unsigned rgb)
{
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0
                                blue:(rgb & 0xFF) / 255.0 alpha:1];
}

@implementation BPColorScheme

- (instancetype)initWithIdentifier:(NSString *)identifier name:(NSString *)name stages:(NSArray<NSColor *> *)stages
                             alpha:(CGFloat)alpha stageEnd:(NSColor *)stageEnd trace:(NSColor *)trace
                         highlight:(NSColor *)highlight
{
    if (self = [super init]) {
        _identifier = identifier;
        _localizedName = name;
        _stageColors = stages;
        _routeAlpha = alpha;
        _stageEndColor = stageEnd;
        _referenceTraceColor = trace;
        _highlightColor = highlight;
        _routeWidth = 8.0;
        _traceAlpha = 0.5;
        _traceWidth = 6.0;
    }
    return self;
}

- (instancetype)withRouteWidth:(CGFloat)routeWidth traceAlpha:(CGFloat)alpha width:(CGFloat)width
{
    _routeWidth = routeWidth;
    _traceAlpha = alpha;
    _traceWidth = width;
    return self;
}

+ (NSArray<BPColorScheme *> *)allSchemes
{
    static NSArray *schemes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        schemes = @[
            // the colors before #71
            [[BPColorScheme alloc] initWithIdentifier:@"classic" name:NSLocalizedString(@"Classic", @"color scheme")
                                               stages:@[ [NSColor blueColor], [NSColor systemPurpleColor] ] alpha:0.5
                                             stageEnd:[NSColor systemPurpleColor] trace:[NSColor orangeColor]
                                            highlight:[NSColor systemPinkColor]],
            // stands out on the OSM+cycle map (cycle routes and roads in blue / red / cyan)
            [[BPColorScheme alloc] initWithIdentifier:@"vivid" name:NSLocalizedString(@"Vivid (OSM+cycle map)", @"color scheme")
                                               stages:@[ BPRGB(0xE6007E), BPRGB(0x00A651) ] alpha:0.75
                                             stageEnd:BPRGB(0xE6007E) trace:BPRGB(0x505050)
                                            highlight:BPRGB(0xFFD400)],
            [[BPColorScheme alloc] initWithIdentifier:@"dark" name:NSLocalizedString(@"Dark", @"color scheme")
                                               stages:@[ BPRGB(0x1A1A1A), BPRGB(0xB0002A) ] alpha:0.75
                                             stageEnd:BPRGB(0xB0002A) trace:BPRGB(0x00B8D4)
                                            highlight:BPRGB(0xFFD400)],
            // light colors, readable on satellite images
            [[BPColorScheme alloc] initWithIdentifier:@"satellite" name:NSLocalizedString(@"Satellite", @"color scheme")
                                               stages:@[ BPRGB(0xFFD60A), BPRGB(0x00E5FF) ] alpha:0.85
                                             stageEnd:BPRGB(0x00E5FF) trace:[NSColor whiteColor]
                                            highlight:BPRGB(0xFF00C8)],
            // to compare a real track (imported trace) with the planned route: the trace red, opaque and wide, the route
            // opaque, narrower, over it (where they coincide: the route with a red border; where they differ: apart)
            [[[BPColorScheme alloc] initWithIdentifier:@"compare" name:NSLocalizedString(@"Compare with trace", @"color scheme")
                                                stages:@[ BPRGB(0x2F6FED), BPRGB(0x7B4FD6) ] alpha:1.0
                                              stageEnd:BPRGB(0x7B4FD6) trace:BPRGB(0xFF1744)
                                             highlight:BPRGB(0xFFD400)] withRouteWidth:5 traceAlpha:1.0 width:10],
        ];
    });
    return schemes;
}

+ (BPColorScheme *)defaultScheme
{
    return [self allSchemes].firstObject;
}

+ (BPColorScheme *)schemeWithIdentifier:(nullable NSString *)identifier
{
    for (BPColorScheme *s in [self allSchemes]) if ([s.identifier isEqualToString:identifier]) return s;
    return [self defaultScheme];
}

+ (BPColorScheme *)currentScheme
{
    return [self schemeWithIdentifier:[[NSUserDefaults standardUserDefaults] stringForKey:BPColorSchemeKey]];
}

- (NSColor *)colorForStage:(NSUInteger)stage
{
    return self.stageColors[stage % self.stageColors.count];
}

- (NSImage *)swatchImage
{
    NSMutableArray<NSColor *> *colors = [self.stageColors mutableCopy];
    [colors addObjectsFromArray:@[ self.referenceTraceColor, self.highlightColor ]];
    const CGFloat w = 14, h = 10, gap = 2;
    NSSize size = NSMakeSize(colors.count * (w + gap) - gap, h);
    return [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect r) {
        for (NSUInteger i = 0; i < colors.count; i++) {
            NSRect cell = NSMakeRect(i * (w + gap), 0, w, h);
            [colors[i] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:cell xRadius:2 yRadius:2] fill];
            [[NSColor colorWithWhite:0.5 alpha:0.6] setStroke];
            [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(cell, 0.5, 0.5) xRadius:2 yRadius:2] stroke];
        }
        return YES;
    }];
}

@end
