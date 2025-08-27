//
//  ExportAccessoryViewController.m
//  BikePlanner
//
//  Created by Daniel Braun on 25/08/2025.
//

#import "ExportAccessoryViewController.h"

@interface ExportAccessoryViewController ()

@end

@implementation ExportAccessoryViewController


- (void) setOutputFormatNum:(int) nv
{
    if (nv == _outputFormatNum) return;
    _outputFormatNum = nv;
    
    
    if (!self.savePanel) return;

    // Update allowed extensions
    NSString *ext = nil;
    switch (nv) {
        default:
        case 0:
            ext = @"gpx";
            break;
        case 1:
            ext = @"fit";
            break;
    }
    self.savePanel.allowedFileTypes = @[ext];

    // Change suggested file extension
    NSString *currentName = self.savePanel.nameFieldStringValue;
    NSString *baseName = [currentName stringByDeletingPathExtension];
    if (baseName.length == 0) {
        baseName = @"route";
    }
    self.savePanel.nameFieldStringValue = [baseName stringByAppendingPathExtension:ext];
}



- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

@end
