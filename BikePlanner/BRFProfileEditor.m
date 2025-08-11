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
@property (strong) NSStackView *stackView;
@property (strong) NSScrollView *scrollView;
@property (copy) NSString *profileName;
//@property (strong) NSMutableArray<NSDictionary *> *parameters;
@property (strong) NSMutableArray<BRFParam *> *parameters;
@end



@implementation BRFProfileEditor

- (instancetype)initWithProfileName:(NSString *)profileName
{
    self = [super initWithWindowNibName:@"BRFProfileEditor"];
    if (self) {
        _profileName = [profileName copy];
        _parameters = [NSMutableArray array];
    }
    return self;
}

- (void) windowDidLoad
{
    [super windowDidLoad];
    self.window.title = [NSString stringWithFormat:@"Edit Profile: %@", self.profileName];

    self.scrollView = [[NSScrollView alloc] initWithFrame:self.window.contentView.bounds];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.hasVerticalScroller = YES;

    self.stackView = [[NSStackView alloc] init];
    self.stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.stackView.spacing = 8;
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;

    self.scrollView.documentView = self.stackView;
    [self.window.contentView addSubview:self.scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor],
        [self.scrollView.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.window.contentView.bottomAnchor]
    ]];

    [self fetchProfile];
}

- (void) fetchProfile {
    NSString *urlStr = [NSString stringWithFormat:@"https://brouter.de/brouter/profiles2/%@.brf", self.profileName];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && !error) {
            NSString *profileText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            [self parseProfile:profileText];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self buildUI];
            });
        }
    }];
    [task resume];
}

#if 1
- (void)parseProfile:(NSString *)brf
{
    [self.parameters removeAllObjects];
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
        [self.parameters addObject:p];
    }
}

#else

- (void)parseProfile:(NSString *)text
{
    NSArray *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        if ([line hasPrefix:@"assign "]) {
            NSArray *parts = [line componentsSeparatedByString:@" "];
            if (parts.count >= 3) {
                NSString *name = parts[1];
                NSString *value = parts[2];
                [self.parameters addObject:@{ @"name": name, @"default": value }];
            }
        }
    }
}
#endif

- (void) buildUI
{
    for (BRFParam *param in self.parameters) {
        [self createRowForParam:param];
    }
    NSButton *doneButton = [NSButton buttonWithTitle:@"Done/Save" target:self action:@selector(doneClicked:)];
    [self.stackView addArrangedSubview:doneButton];
}

- (void)createRowForParam:(BRFParam *)param {
    NSStackView *rowView = [[NSStackView alloc] init];
    rowView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    rowView.spacing = 8;

    NSButton *overrideCheckbox = [NSButton checkboxWithTitle:@"Override" target:nil action:nil];
    NSTextField *label = [NSTextField labelWithString:param.name];
    NSTextField *valueField = [[NSTextField alloc] init];
    valueField.stringValue = param.defaultValue;

    [rowView addArrangedSubview:overrideCheckbox];
    [rowView addArrangedSubview:label];
    [rowView addArrangedSubview:valueField];

    [self.stackView addArrangedSubview:rowView];
}

- (void)doneClicked:(id)sender
{
    NSMutableArray *overrides = [NSMutableArray array];
    for (NSView *row in self.stackView.arrangedSubviews) {
        if (![row isKindOfClass:[NSStackView class]]) continue;
        NSStackView *rowView = (NSStackView *)row;
        if (rowView.arrangedSubviews.count < 3) continue;
        NSButton *check = (NSButton *)rowView.arrangedSubviews[0];
        NSTextField *label = (NSTextField *)rowView.arrangedSubviews[1];
        NSTextField *field = (NSTextField *)rowView.arrangedSubviews[2];
        if (check.state == NSControlStateValueOn) {
            [overrides addObject:[NSString stringWithFormat:@"profile:%@=%@", label.stringValue, field.stringValue]];
        }
    }
    // NSString *extraParams = [overrides componentsJoinedByString:@"|"];
    //if (self.completionHandler) self.completionHandler(extraParams);
    if (self.completionHandler) self.completionHandler(overrides);
    [self.window close];
}

@end
