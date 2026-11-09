//
//  DCOBackgroundView.m
//  Balthisar Tidy
//
//  Created by Jim Derry on 8/29/18.
//  Copyright © 2018 Jim Derry. All rights reserved.
//

#import "DCOBackgroundView.h"

@interface DCOBackgroundView ()

@property (strong) CALayer *bottomBorder;

@end

@implementation DCOBackgroundView

@synthesize backgroundColor = _backgroundColor;
@synthesize trimColor = _trimColor;

#pragma mark - Overridden Methods

- (instancetype)initWithFrame:(NSRect)frameRect {
    if (self = [super initWithFrame:frameRect]) {
        self.wantsLayer = YES;
        
        // Add bottom border
        self.bottomBorder = [CALayer layer];
        self.bottomBorder.borderWidth = 1;
        self.bottomBorder.frame = CGRectMake(-1.f, .0f, CGRectGetWidth(self.frame) + 2.f, CGRectGetHeight(self.frame) + 1.f);
        self.bottomBorder.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable;
        [self.layer addSublayer:self.bottomBorder];
    }
    
    return self;
}

- (void)updateLayer {
    // Update with new color definitions.
    self.layer.backgroundColor = self.backgroundColor.CGColor;
    self.bottomBorder.borderColor = self.trimColor.CGColor;
}

#pragma mark - Getters/Setters

- (NSColor *)backgroundColor {
    if (!_backgroundColor) {
        _backgroundColor = [NSColor textBackgroundColor];
    }
    
    return _backgroundColor;
}

- (void)setBackgroundColor:(NSColor *)backgroundColor {
    _backgroundColor = backgroundColor;
}

- (NSColor *)trimColor {
    if (!_trimColor) {
        // BikePlanner: deprecated since macOS 11, kept as is (#58)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        _trimColor = [NSColor windowFrameColor];
#pragma clang diagnostic pop
    }
    
    return _trimColor;
}

- (void) setTrimColor:(NSColor *)trimColor {
    _trimColor = trimColor;
}

@end
