//
//  PreviewProvider.h
//  BikePlannerQuickLook
//
//  Quick Look preview of BikePlanner documents and GPX files (#70): the route on an Apple Maps snapshot with a summary
//  (BPRoutePreview). Data-based preview: Quick Look shows the image drawn here.
//

#import <Cocoa/Cocoa.h>
#import <QuickLookUI/QuickLookUI.h>

NS_ASSUME_NONNULL_BEGIN

@interface PreviewProvider : QLPreviewProvider <QLPreviewingController>
@end

NS_ASSUME_NONNULL_END
