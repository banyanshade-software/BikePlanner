//
//  main.m
//  RideAnalyzer
//
//  No main nib: the menu is built by RAAppDelegate.
//

#import <Cocoa/Cocoa.h>
#import "RAAppDelegate.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        RAAppDelegate *delegate = [[RAAppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
