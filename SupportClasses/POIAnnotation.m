//
//  POIAnnotation.m
//  BikePlanner
//
//  Created by Daniel Braun on 17/08/2025.
//

#import "POIAnnotation.h"

@implementation POIAnnotation

+ (nullable NSImage *) glyphImageForType:(PoiType_t)type
{
    static NSImage *tpl_toilets = nil;
    static NSImage *tpl_water = nil;
    static NSImage *tpl_cemetery = nil;
    static NSImage *tpl_repair = nil;
    static NSImage *tpl_warning = nil;

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
        tpl_warning = [NSImage imageNamed:@"icon_warning"];
        [tpl_warning setTemplate:YES];
    });
    switch (type) {
        case POI_drinking_water:         return tpl_water;
        case POI_toilets:                return tpl_toilets;
        case POI_cemetery:               return tpl_cemetery;
        case POI_bicycle_repair_station: return tpl_repair;
        case POI_warning:                return tpl_warning;
        case POI_food:      return [NSImage imageWithSystemSymbolName:@"fork.knife" accessibilityDescription:nil];
        case POI_shelter:   return [NSImage imageWithSystemSymbolName:@"house" accessibilityDescription:nil];
        case POI_viewpoint: return [NSImage imageWithSystemSymbolName:@"binoculars" accessibilityDescription:nil];
        case POI_campsite:  return [NSImage imageWithSystemSymbolName:@"flame" accessibilityDescription:nil];
        case POI_store:     return [NSImage imageWithSystemSymbolName:@"cart" accessibilityDescription:nil];
        case POI_info:      return [NSImage imageWithSystemSymbolName:@"info" accessibilityDescription:nil];
        case POI_generic:   return [NSImage imageWithSystemSymbolName:@"mappin" accessibilityDescription:nil];
        case POI_unknown:   return nil;
    }
    return nil;
}

+ (nullable NSColor *) tintColorForType:(PoiType_t)type
{
    switch (type) {
        case POI_drinking_water:         return [NSColor systemBlueColor];
        case POI_toilets:                return [NSColor greenColor];
        case POI_cemetery:               return [NSColor colorWithRed:0. green:0. blue:1. alpha:0.2];
        case POI_bicycle_repair_station: return [NSColor cyanColor];
        case POI_warning:                return [NSColor orangeColor];
        case POI_food:                   return [NSColor systemBrownColor];
        case POI_shelter:                return [NSColor systemTealColor];
        case POI_viewpoint:              return [NSColor systemPurpleColor];
        case POI_campsite:               return [NSColor systemGreenColor];
        case POI_store:                  return [NSColor systemPinkColor];
        case POI_info:                   return [NSColor systemIndigoColor];
        case POI_generic:                return [NSColor systemGrayColor];
        case POI_unknown:                return nil;
    }
    return nil;
}

- (void) configureAnnotViewIcon:(MKMarkerAnnotationView *)view
{
    NSAssert(view.annotation, @"no annotation");
    NSAssert([view.annotation isKindOfClass:[self class]], @"bad class");
    NSAssert(view.annotation==self, @"should be self");

    NSImage *glyph = [[self class] glyphImageForType:_poiType];
    NSColor *tint = [[self class] tintColorForType:_poiType];
    if (glyph) view.glyphImage = glyph;
    if (tint) view.markerTintColor = tint;
    if (_poiType == POI_drinking_water) view.displayPriority = MKFeatureDisplayPriorityDefaultHigh;
    if (_poiType == POI_toilets) view.displayPriority = MKFeatureDisplayPriorityDefaultLow+1.;
    // excluded from the export (#5): greyed (views are reused: always set)
    if (_excluded) view.markerTintColor = [NSColor systemGrayColor];
    view.alphaValue = _excluded ? 0.6 : 1.0;
}
// <a href="https://www.flaticon.com/free-icons/drinkable" title="drinkable icons">Drinkable icons created by cube29 - Flaticon</a>
// <a href="https://www.flaticon.com/free-icons/restroom" title="restroom icons">Restroom icons created by monkik - Flaticon</a>
// <a href="https://www.flaticon.com/free-icons/error" title="error icons">Error icons created by Gregor Cresnar - Flaticon</a>


// SVG icons :https://github.com/mapbox/maki/tree/main/icons
@end



@implementation POICustomAnnotation

@end
