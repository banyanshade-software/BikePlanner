//
//  ExportAccessoryViewController.h
//  BikePlanner
//
//  Created by Daniel Braun on 25/08/2025.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface ExportAccessoryViewController : NSViewController
@property (weak) IBOutlet NSButton *poiCheckbox;
@property (assign, nonatomic) int outputFormatNum;
@property (weak) NSSavePanel *savePanel;
@end

NS_ASSUME_NONNULL_END
