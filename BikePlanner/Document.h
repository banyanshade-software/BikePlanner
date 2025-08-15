//
//  Document.h
//  BikePlanner
//
//  Created by Daniel on 15/08/2025.
//

#import <Cocoa/Cocoa.h>

@class MapController;

@interface Document : NSDocument

@property (weak) IBOutlet MapController *mapController;

@end

