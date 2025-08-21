//
//  POICalloutView.m
//  BikePlanner
//
//  Created by Daniel Braun on 20/08/2025.
//

#import "POICalloutView.h"

@implementation POICalloutView {
    NSTextField *_infoLabel;
    NSSegmentedControl *_excludeControl;
}

@synthesize excludeControl = _excludeControl;

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Text view
        _infoLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _infoLabel.editable = NO;
        _infoLabel.bezeled = NO;
        _infoLabel.drawsBackground = NO;
        _infoLabel.lineBreakMode = NSLineBreakByWordWrapping;
        _infoLabel.usesSingleLineMode = NO;
        _infoLabel.font = [NSFont systemFontOfSize:12];
        _infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _infoLabel.stringValue = @"coucou";
        [self addSubview:_infoLabel];
        
        // Segmented control
        _excludeControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(14, 64, 280, 56)];
        _excludeControl.segmentCount = 2;
        _excludeControl.selectedSegment = 0;
        [_excludeControl setLabel:@"Include" forSegment:0];
        [_excludeControl setLabel:@"Exclude" forSegment:1];

        _excludeControl.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_excludeControl];
        
        // Auto Layout
        [NSLayoutConstraint activateConstraints:@[
            [_infoLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
            [_infoLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
            [_infoLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
            
            [_excludeControl.topAnchor constraintEqualToAnchor:_infoLabel.bottomAnchor constant:6],
            [_excludeControl.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
            [_excludeControl.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4],
            [_excludeControl.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4],
        ]];
    }
    return self;
}

- (void) setInfodic:(NSDictionary *)dic
{
    if (_infodic == dic) return;
    _infodic = dic;
    _infoLabel.stringValue = [dic description];
    [self setNeedsDisplay:YES];
}

- (void) mouseDown:(NSEvent *)event
{
    [self.annotview  setSelected:NO animated:YES];
}
@end
