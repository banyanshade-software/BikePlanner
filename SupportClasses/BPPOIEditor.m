//
//  BPPOIEditor.m
//  BikePlanner
//
//  Sheet asking the type and the name of a custom POI (#3).
//

#import "BPPOIEditor.h"

@implementation BPPOIEditor

+ (void)editType:(PoiType_t)type name:(nullable NSString *)name title:(NSString *)title
        okButton:(NSString *)okTitle window:(nullable NSWindow *)window
      completion:(void (^)(PoiType_t type, NSString *name))completion
{
    if (!window) {
        completion(type, name ?: @"");
        return;
    }
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 30, 240, 26) pullsDown:NO];
    popup.accessibilityIdentifier = @"poiType";
    for (NSNumber *t in [POILocation customPoiTypes]) {
        [popup addItemWithTitle:[POILocation displayNameForType:t.intValue]];
        popup.lastItem.tag = t.intValue;
    }
    if (![popup selectItemWithTag:type]) [popup selectItemWithTag:POI_warning];

    NSTextField *field = [NSTextField textFieldWithString:name ?: @""];
    field.frame = NSMakeRect(0, 0, 240, 22);
    field.placeholderString = NSLocalizedString(@"Name (optional)", @"custom POI editor");
    field.accessibilityIdentifier = @"poiName";

    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 58)];
    [accessory addSubview:popup];
    [accessory addSubview:field];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = NSLocalizedString(@"Type and name of the point of interest. The name is exported to the GPX.",
                                              @"custom POI editor");
    alert.accessoryView = accessory;
    [alert addButtonWithTitle:okTitle];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"custom POI editor")];
    alert.window.initialFirstResponder = field;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        completion((PoiType_t)popup.selectedTag, field.stringValue);
    }];
}

@end
