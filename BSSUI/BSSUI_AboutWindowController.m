//
//  BSSUI_AboutWindowController.m
//  BSSUI
//
//  Created by Daniel BRAUN on 05/03/2015.
//  Copyright (c) 2015 Daniel BRAUN. All rights reserved.
//

#import "BSSUI_AboutWindowController.h"

@interface BSSUI_AboutWindowController ()

@end

@implementation BSSUI_AboutWindowController {
    BOOL pauseScrolling;
    NSTimer *timer;
    CGFloat scrolly;
    
    NSString *ackpath;
    BOOL resendackpath;
}

@synthesize scrollView = _scrollView;


- (void)windowDidLoad {
    [super windowDidLoad];
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}


- (BOOL)windowShouldClose:(id)sender
{
    [self stopScroll];
    return YES;
}
- (IBAction)showWindow:(id)sender
{
    [super showWindow:sender];
    [self startScroll];
}

- (void) startScroll
{
    pauseScrolling = NO;
    scrolly = 0;
    //NSScrollView
   
    
    timer = [NSTimer scheduledTimerWithTimeInterval:0.04 target:self selector:@selector(scrollText) userInfo:nil repeats:YES];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scrolledNotif:) name:NSScrollViewWillStartLiveScrollNotification object:_scrollView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scrolledNotif:) name:NSScrollViewWillStartLiveScrollNotification object:_scrollView];
}
- (void) stopScroll
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [timer invalidate];
    timer = nil;
}
- (void) scrolledNotif:(NSNotification *)n
{
    NSLog(@"stop scrolling due to user (%@)\n", n.name);
    NSAssert(n.object == _scrollView, @"hu?");
    [self stopScroll];
}
- (void) scrollText
{
    if (pauseScrolling) return;
    //if ([[_scrollView documentView] isFlipped]) {
    //    NSLog(@"scrolling not supported for flipped view\n");
    //    //return;
    //}
    CGPoint p = NSMakePoint(0, scrolly);
    scrolly += 1;
    [[_scrollView documentView] scrollPoint:p];
    if (1.0==_scrollView.verticalScroller.floatValue) {
        NSLog(@"stop scrolling due to end (%f) %f\n",  scrolly,  _scrollView.verticalScroller.floatValue);
        [self stopScroll];
    }
}

#pragma mark -


- (void) awakeFromNib
{
    [super awakeFromNib];
    if (resendackpath) {
        // in case setAcknowledgmentsPath: was called before awakeFromNib
        [super setAcknowledgmentsPath:ackpath];
    }
}
- (void)setAcknowledgmentsPath:(NSString *)acknowledgmentsPath
{
    ackpath = acknowledgmentsPath;
    resendackpath = YES;
    [super setAcknowledgmentsPath:acknowledgmentsPath];
}
@end
