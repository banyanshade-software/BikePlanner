//
//  BRFProfileEditor.m
//  BikePlanner
//
//  Created by Daniel on 10/08/2025.
//

#import "BRFProfileEditor.h"

@implementation BRFParam
@end

@interface BRFProfileEditor ()
@property (nonatomic, strong) NSURL *profileURL;
@property (nonatomic, copy) NSString *profileName;
@property (nonatomic, strong) NSMutableArray<BRFParam *> *params;
@property (nonatomic, strong) NSStackView *stack;
@end

@implementation BRFProfileEditor

- (instancetype)initWithProfileURL:(NSURL *)url profileName:(NSString *)profileName {
    self = [super initWithWindow:nil];
    if (self) {
        _profileURL = url;
        _profileName = [profileName copy];
        _params = [NSMutableArray array];
        [self buildWindow];
    }
    return self;
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 560, 420);
    NSWindow *w = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    w.title = [NSString stringWithFormat:@"Edit profile: %@", self.profileName ?: @"profile"];
    self.window = w;

    NSView *content = w.contentView;

    // Stack view to hold rows
    self.stack = [[NSStackView alloc] initWithFrame:NSMakeRect(10, 60, frame.size.width-20, frame.size.height-80)];
    self.stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.stack.alignment = NSLayoutAttributeLeading;
    self.stack.spacing = 6;
    self.stack.edgeInsets = NSEdgeInsetsMake(6, 6, 6, 6);
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:self.stack.frame];
    scroll.hasVerticalScroller = YES;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.documentView = self.stack;
    [content addSubview:scroll];

    // Buttons
    NSButton *ok = [[NSButton alloc] initWithFrame:NSMakeRect(frame.size.width - 180, 18, 80, 30)];
    ok.title = @"OK"; ok.bezelStyle = NSBezelStyleRounded; ok.target = self; ok.action = @selector(okAction:);
    [content addSubview:ok];

    NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(frame.size.width - 90, 18, 80, 30)];
    cancel.title = @"Cancel"; cancel.bezelStyle = NSBezelStyleRounded; cancel.target = self; cancel.action = @selector(cancelAction:);
    [content addSubview:cancel];

    // status label
    NSTextField *lbl = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 18, frame.size.width - 200, 30)];
    lbl.bezeled = NO; lbl.drawsBackground = NO; lbl.editable = NO; lbl.selectable = NO;
    lbl.stringValue = @"Loading profile...";
    lbl.tag = 999;
    [content addSubview:lbl];

    // Auto layout for scroll
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:content.topAnchor constant:10],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:10],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-10],
        [scroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-60]
    ]];
}

- (void)showEditor {
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [self fetchProfile];
}

#pragma mark - Networking + parsing

- (void)fetchProfile {
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithURL:self.profileURL completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSTextField *lbl = [self.window.contentView viewWithTag:999];
            if (error || !data) {
                lbl.stringValue = [NSString stringWithFormat:@"Failed to load profile: %@", error.localizedDescription ?: @"no data"];
                return;
            }
            NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (!text) {
                lbl.stringValue = @"Failed to decode profile text";
                return;
            }
            lbl.stringValue = @"Profile loaded";
            [self parseBRFText:text];
            [self buildFormUI];
        });
    }];
    [task resume];
}

- (void)parseBRFText:(NSString *)brf
{
    [self.params removeAllObjects];
    NSError *err = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"assign\\s+(\\w+)\\s*=\\s*([\\d\\.\\-]+)"
                options:NSRegularExpressionCaseInsensitive error:&err];
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:brf options:0 range:NSMakeRange(0, brf.length)];
    for (NSTextCheckingResult *m in matches) {
        if (m.numberOfRanges < 3) continue;
        NSString *name = [brf substringWithRange:[m rangeAtIndex:1]];
        NSString *val = [brf substringWithRange:[m rangeAtIndex:2]];
        BRFParam *p = [BRFParam new];
        p.name = name;
        p.defaultValue = val;
        p.isBoolean = ([val isEqualToString:@"0"] || [val isEqualToString:@"1"]);
        [self.params addObject:p];
    }
}

#pragma mark - UI building

- (void)buildFormUI {
    // Clear existing arranged subviews
    for (NSView *sv in [self.stack.arrangedSubviews copy]) {
        [self.stack removeArrangedSubview:sv];
        [sv removeFromSuperview];
    }

    for (BRFParam *p in self.params) {
        NSView *row = [self createRowForParam:p];

        [self.stack addArrangedSubview:row];
    }
    [self.stack layoutSubtreeIfNeeded];
}

- (NSView *)createRowForParam:(BRFParam *)p {
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, self.window.contentView.frame.size.width-40, 30)];

    // Override checkbox
    NSButton *overrideBtn = [[NSButton alloc] initWithFrame:NSMakeRect(4, 4, 18, 18)];
    overrideBtn.buttonType = NSButtonTypeSwitch;
    overrideBtn.state = NSControlStateValueOff;
    p.overrideButton = overrideBtn;
    [container addSubview:overrideBtn];

    // Label
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(30, 4, 200, 20)];
    label.bezeled = NO; label.drawsBackground = NO; label.editable = NO; label.selectable = NO;
    label.stringValue = [NSString stringWithFormat:@"%@ (default: %@)", p.name, p.defaultValue];
    [container addSubview:label];

    // Value control: choose type by heuristics
    NSView *control = nil;
    if (p.isBoolean) {
        // Use a checkbox as value control
        NSButton *valBtn = [[NSButton alloc] initWithFrame:NSMakeRect(250, 2, 100, 24)];
        valBtn.buttonType = NSButtonTypeSwitch;
        valBtn.state = ([p.defaultValue isEqualToString:@"1"] ? NSControlStateValueOn : NSControlStateValueOff);
        valBtn.enabled = NO; // disabled until override checked
        control = valBtn;
    } else {
        // numeric value: if magnitude reasonable, use slider+field
        double d = [p.defaultValue doubleValue];
        double mag = fabs(d);
        if (mag > 0 && mag <= 1000) {
            // create slider
            NSSlider *slider = [[NSSlider alloc] initWithFrame:NSMakeRect(250, 6, 180, 20)];
            slider.minValue = (d <= 0 ? d*2 : 0);
            slider.maxValue = (d <= 0 ? 0 : MAX(d*2, 10));
            slider.doubleValue = d;
            slider.enabled = NO;

            NSTextField *valField = [[NSTextField alloc] initWithFrame:NSMakeRect(440, 4, 80, 22)];
            valField.stringValue = p.defaultValue;
            valField.editable = NO; valField.enabled = NO;

            // bind slider -> field
            [slider setTarget:self];
            [slider setAction:@selector(sliderChanged:)];
            slider.identifier = valField.identifier = [NSString stringWithFormat:@"%@_id", p.name];

            [container addSubview:slider];
            [container addSubview:valField];
            control = slider; // store slider as control; value will be read from field by id
        } else {
            // fallback to text field
            NSTextField *valField = [[NSTextField alloc] initWithFrame:NSMakeRect(250, 4, 180, 22)];
            valField.stringValue = p.defaultValue;
            valField.enabled = NO;
            control = valField;
        }
    }

    if (control) {
        // place at x=250 if not already added
        if (control.superview != container) {
            control.frame = NSMakeRect(250, control.frame.origin.y, control.frame.size.width, control.frame.size.height);
            [container addSubview:control];
        }
        p.valueControl = control;
    }

    // Hook override checkbox toggling to enable/disable value control
    overrideBtn.target = self;
    overrideBtn.action = @selector(overrideToggled:);
    overrideBtn.identifier = p.name;

    return container;
}

- (void)sliderChanged:(NSSlider *)slider {
    // find value field by identifier pattern
    // we stored identifier as string like "name_id" in slider and text field
    NSString *ident = slider.identifier;
    if (!ident) return;
    // find all subviews for identifier and update text fields
    for (NSView *row in self.stack.arrangedSubviews) {
        for (NSView *v in row.subviews) {
            if ([v isKindOfClass:[NSTextField class]] && v.identifier && [v.identifier isEqualTo:ident]) {
                NSTextField *tf = (NSTextField *)v;
                tf.stringValue = [NSString stringWithFormat:@"%g", slider.doubleValue];
            }
        }
    }
}

- (void)overrideToggled:(NSButton *)sender {
    NSString *paramName = sender.identifier;
    BRFParam *found = nil;
    for (BRFParam *p in self.params) {
        if ([p.name isEqualToString:paramName]) { found = p; break; }
    }
    if (!found) return;
    BOOL enabled = (sender.state == NSControlStateValueOn);
    if ([found.valueControl isKindOfClass:[NSTextField class]]) {
        NSTextField *tf = (NSTextField *)found.valueControl;
        tf.enabled = enabled;
    } else if ([found.valueControl isKindOfClass:[NSSlider class]]) {
        NSSlider *s = (NSSlider *)found.valueControl;
        s.enabled = enabled;
        // find companion text field and enable it
        NSString *ident = s.identifier;
        for (NSView *row in self.stack.arrangedSubviews) {
            for (NSView *v in row.subviews) {
                if ([v isKindOfClass:[NSTextField class]] && v.identifier && [v.identifier isEqualTo:ident]) {
                    ((NSTextField *) v).enabled = enabled;
                }
            }
        }
    } else if ([found.valueControl isKindOfClass:[NSButton class]]) {
        NSButton *b = (NSButton *)found.valueControl;
        b.enabled = enabled;
    }
}

#pragma mark - Actions

- (void)okAction:(id)sender {
    NSMutableArray *pairs = [NSMutableArray array];
    for (BRFParam *p in self.params) {
        if (p.overrideButton.state != NSControlStateValueOn) continue;
        NSString *value = nil;
        if ([p.valueControl isKindOfClass:[NSTextField class]]) {
            value = ((NSTextField *)p.valueControl).stringValue;
        } else if ([p.valueControl isKindOfClass:[NSSlider class]]) {
            NSSlider *s = (NSSlider *)p.valueControl;
            // find companion text field
            NSString *ident = s.identifier;
            for (NSView *row in self.stack.arrangedSubviews) {
                for (NSView *v in row.subviews) {
                    if ([v isKindOfClass:[NSTextField class]] && v.identifier && [v.identifier isEqualTo:ident]) {
                        value = ((NSTextField *)v).stringValue;
                        break;
                    }
                }
                if (value) break;
            }
            if (!value) value = [NSString stringWithFormat:@"%g", s.doubleValue];
        } else if ([p.valueControl isKindOfClass:[NSButton class]]) {
            NSButton *b = (NSButton *)p.valueControl;
            value = (b.state == NSControlStateValueOn) ? @"1" : @"0";
        }
        if (!value) continue;
        NSString *pair = [NSString stringWithFormat:@"%@=%@", p.name, value];
        [pairs addObject:pair];
    }
    NSString *extraParams = pairs.count ? [pairs componentsJoinedByString:@"|"] : nil;
    if (self.completion) self.completion(extraParams);
    [self.window orderOut:nil];
}

- (void)cancelAction:(id)sender {
    if (self.completion) self.completion(nil);
    [self.window orderOut:nil];
}

@end


// Example usage (call from your app controller):
// NSURL *url = [NSURL URLWithString:@"https://brouter.de/brouter/profiles2/trekking.brf"];
// BRFProfileEditor *editor = [[BRFProfileEditor alloc] initWithProfileURL:url profileName:@"trekking"];
// editor.completion = ^(NSString * _Nullable extraParams) {
//     if (extraParams) {
//         NSLog(@"User overrides: %@", extraParams);
//         // append to request as &extraParams=... (remember to percent-encode later)
//     } else {
//         NSLog(@"User cancelled");
//     }
// };
// [editor showEditor];
