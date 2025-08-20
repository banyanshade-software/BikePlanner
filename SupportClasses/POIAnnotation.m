//
//  POIAnnotation.m
//  BikePlanner
//
//  Created by Daniel Braun on 17/08/2025.
//

#import "POIAnnotation.h"

@implementation POIAnnotation

- (void) configureAnnotViewIcon:(MKMarkerAnnotationView *)view
{
    static NSImage *tpl_toilets = nil;
    static NSImage *tpl_water = nil;
    static NSImage *tpl_cemetery = nil;
    static NSImage *tpl_repair = nil;

    static dispatch_once_t onceToken = (dispatch_once_t)0;
    dispatch_once(&onceToken, ^{
        tpl_water = [NSImage imageNamed:@"icon_water"];
        [tpl_water setTemplate:YES];
        tpl_toilets = [NSImage imageNamed:@"icon_toilets"];
        [tpl_toilets setTemplate:YES];
        tpl_cemetery = [NSImage imageNamed:@"icon_cemetery"];
        [tpl_cemetery setTemplate:YES];
        tpl_repair = [NSImage imageNamed:@"icon_repair"];
        [tpl_repair setTemplate:YES];
    });
    
    NSAssert(view.annotation, @"no annotation");
    NSAssert([view.annotation isKindOfClass:[self class]], @"bad class");
    NSAssert(view.annotation==self, @"should be self");
    
    switch (_poiType) {
        case POI_drinking_water:
            view.glyphImage = tpl_water;
            view.displayPriority = MKFeatureDisplayPriorityDefaultHigh;
            view.markerTintColor = [NSColor systemBlueColor];
            break;
        case POI_toilets:
            view.glyphImage = tpl_toilets;
            view.displayPriority = MKFeatureDisplayPriorityDefaultLow+1.;
            view.markerTintColor = [NSColor greenColor];
            break;
        case POI_cemetery:
            view.glyphImage = tpl_cemetery;
            view.markerTintColor = [NSColor colorWithRed:0. green:0. blue:1. alpha:0.2];
            break;
        case POI_bicycle_repair_station:
            view.glyphImage = tpl_repair;
            view.markerTintColor = [NSColor orangeColor];
            break;
        default:
            break;
    }
    
}
// <a href="https://www.flaticon.com/free-icons/drinkable" title="drinkable icons">Drinkable icons created by cube29 - Flaticon</a>
//<a href="https://www.flaticon.com/free-icons/restroom" title="restroom icons">Restroom icons created by monkik - Flaticon</a>
@end
