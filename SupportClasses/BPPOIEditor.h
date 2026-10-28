//
//  BPPOIEditor.h
//  BikePlanner
//
//  Sheet asking the type and the name of a custom POI (#3).
//

#import <Cocoa/Cocoa.h>
#import "POILocation.h"

NS_ASSUME_NONNULL_BEGIN

@interface BPPOIEditor : NSObject

/// Shows a sheet on window with a type pop-up (accessibility identifier "poiType", item tag = PoiType_t) and a name
/// field ("poiName"); completion is called on OK only. Without window, completion is called at once with the
/// given values.
+ (void)editType:(PoiType_t)type name:(nullable NSString *)name title:(NSString *)title
        okButton:(NSString *)okTitle window:(nullable NSWindow *)window
      completion:(void (^)(PoiType_t type, NSString *name))completion;

@end

NS_ASSUME_NONNULL_END
