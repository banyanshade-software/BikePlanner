//
//  RAFilterSheet.m
//  RideAnalyzer
//

#import "RAFilterSheet.h"
#import "RAFilter.h"

@interface RAFilterSheet () <NSTokenFieldDelegate>
@end

@implementation RAFilterSheet
{
    NSArray<NSString *> *_deviceKeys;
    NSArray<NSString *> *_allTags;
    void (^_completion)(RAFilter *);
}

- (NSTextField *)numberFieldWithValue:(double)value identifier:(NSString *)identifier
{
    NSTextField *f = [NSTextField textFieldWithString:value > 0 ? [NSString stringWithFormat:@"%g", value] : @""];
    NSNumberFormatter *nf = [[NSNumberFormatter alloc] init];
    nf.numberStyle = NSNumberFormatterDecimalStyle;
    nf.minimum = @0;
    f.formatter = nf;
    f.placeholderString = NSLocalizedString(@"any", @"filter: no limit");
    f.identifier = identifier;
    [f.widthAnchor constraintEqualToConstant:70].active = YES;
    return f;
}

- (NSDatePicker *)datePicker:(nullable NSDate *)date
{
    NSDatePicker *p = [[NSDatePicker alloc] init];
    p.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    p.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    p.dateValue = date ?: [NSDate date];
    return p;
}

- (instancetype)initWithFilter:(RAFilter *)filter devices:(NSArray<NSArray<NSString *> *> *)devices
                          tags:(NSArray<NSString *> *)tags
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 460, 300)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    self = [super initWithWindow:window];
    if (!self) return nil;
    _allTags = [tags copy];
    NSTextField *title = [NSTextField labelWithString:NSLocalizedString(@"Filter the Rides", @"filter sheet")];
    title.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize + 1];

    _fromCheckbox = [NSButton checkboxWithTitle:NSLocalizedString(@"From", @"filter sheet") target:self action:@selector(update:)];
    _fromCheckbox.state = filter.fromDay ? NSControlStateValueOn : NSControlStateValueOff;
    _fromPicker = [self datePicker:filter.fromDay];
    _toCheckbox = [NSButton checkboxWithTitle:NSLocalizedString(@"to", @"filter sheet") target:self action:@selector(update:)];
    _toCheckbox.state = filter.toDay ? NSControlStateValueOn : NSControlStateValueOff;
    _toPicker = [self datePicker:filter.toDay];
    NSStackView *period = [NSStackView stackViewWithViews:@[ _fromCheckbox, _fromPicker, _toCheckbox, _toPicker ]];

    _minDistanceField = [self numberFieldWithValue:filter.minDistance / 1000 identifier:@"filterMinKm"];
    _maxDistanceField = [self numberFieldWithValue:filter.maxDistance / 1000 identifier:@"filterMaxKm"];
    _minAscentField = [self numberFieldWithValue:filter.minAscent identifier:@"filterMinAscent"];
    NSStackView *distance = [NSStackView stackViewWithViews:@[
        [NSTextField labelWithString:NSLocalizedString(@"Distance from", @"filter sheet")], _minDistanceField,
        [NSTextField labelWithString:NSLocalizedString(@"to", @"filter sheet")], _maxDistanceField,
        [NSTextField labelWithString:@"km"] ]];
    NSStackView *ascent = [NSStackView stackViewWithViews:@[
        [NSTextField labelWithString:NSLocalizedString(@"Ascent at least", @"filter sheet")], _minAscentField,
        [NSTextField labelWithString:@"m"] ]];

    NSMutableArray<NSButton *> *boxes = [NSMutableArray array];
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSArray<NSString *> *d in devices) {
        NSButton *b = [NSButton checkboxWithTitle:d[1] target:nil action:NULL];
        b.state = [filter.deviceKeys containsObject:d[0]] ? NSControlStateValueOn : NSControlStateValueOff;
        b.identifier = [@"filterDevice." stringByAppendingString:d[0]];
        [boxes addObject:b];
        [keys addObject:d[0]];
    }
    _deviceCheckboxes = boxes;
    _deviceKeys = keys;
    NSTextField *devicesLabel = [NSTextField labelWithString:NSLocalizedString(@"Devices (none checked: all)", @"filter sheet")];
    NSStackView *deviceList = [NSStackView stackViewWithViews:boxes];
    deviceList.orientation = NSUserInterfaceLayoutOrientationVertical;
    deviceList.alignment = NSLayoutAttributeLeading;
    deviceList.edgeInsets = NSEdgeInsetsMake(0, 16, 0, 0);

    _tagsField = [[NSTokenField alloc] init];
    _tagsField.objectValue = [filter.tags.allObjects sortedArrayUsingSelector:@selector(compare:)];
    _tagsField.placeholderString = NSLocalizedString(@"Tags (any of them)", @"filter sheet");
    _tagsField.delegate = self;
    [_tagsField.widthAnchor constraintEqualToConstant:420].active = YES;

    NSButton *cancel = [NSButton buttonWithTitle:NSLocalizedString(@"Cancel", @"button") target:self action:@selector(cancel:)];
    cancel.keyEquivalent = @"\033";
    NSButton *apply = [NSButton buttonWithTitle:NSLocalizedString(@"Apply", @"button") target:self action:@selector(apply:)];
    apply.keyEquivalent = @"\r";
    NSStackView *buttons = [NSStackView stackViewWithViews:@[ cancel, apply ]];

    NSMutableArray<NSView *> *views = [@[ title, period, distance, ascent ] mutableCopy];
    if (boxes.count) [views addObjectsFromArray:@[ devicesLabel, deviceList ]];
    [views addObjectsFromArray:@[ _tagsField, buttons ]];
    NSStackView *content = [NSStackView stackViewWithViews:views];
    content.orientation = NSUserInterfaceLayoutOrientationVertical;
    content.alignment = NSLayoutAttributeLeading;
    content.spacing = 10;
    content.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    [buttons.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20].active = YES;
    window.contentView = content;
    [self update:self];
    return self;
}

- (void)update:(id)sender
{
    _fromPicker.enabled = _fromCheckbox.state == NSControlStateValueOn;
    _toPicker.enabled = _toCheckbox.state == NSControlStateValueOn;
}

- (RAFilter *)editedFilter
{
    RAFilter *f = [[RAFilter alloc] init];
    NSCalendar *cal = [NSCalendar currentCalendar];
    if (_fromCheckbox.state == NSControlStateValueOn) f.fromDay = [cal startOfDayForDate:_fromPicker.dateValue];
    if (_toCheckbox.state == NSControlStateValueOn) f.toDay = [cal startOfDayForDate:_toPicker.dateValue];
    f.minDistance = MAX(0, _minDistanceField.doubleValue) * 1000;
    f.maxDistance = MAX(0, _maxDistanceField.doubleValue) * 1000;
    f.minAscent = MAX(0, _minAscentField.doubleValue);
    NSMutableSet<NSString *> *devices = [NSMutableSet set];
    for (NSUInteger i = 0; i < _deviceCheckboxes.count; i++) {
        if (_deviceCheckboxes[i].state == NSControlStateValueOn) [devices addObject:_deviceKeys[i]];
    }
    f.deviceKeys = devices;
    NSMutableSet<NSString *> *tags = [NSMutableSet set];
    if ([_tagsField.objectValue isKindOfClass:[NSArray class]]) {
        for (id t in _tagsField.objectValue) {
            NSString *s = [t isKindOfClass:[NSString class]]
                ? [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
            if ([s hasPrefix:@"#"]) s = [s substringFromIndex:1];
            if (s.length) [tags addObject:s];
        }
    }
    f.tags = tags;
    return f;
}

- (void)beginSheetForWindow:(NSWindow *)window completion:(void (^)(RAFilter * _Nullable filter))completion
{
    _completion = [completion copy];
    [window beginSheet:self.window completionHandler:nil];
}

- (void)endWithFilter:(nullable RAFilter *)filter
{
    void (^completion)(RAFilter *) = _completion;
    _completion = nil;
    if (self.window.sheetParent) [self.window.sheetParent endSheet:self.window];
    if (completion) completion(filter);
}

- (IBAction)apply:(nullable id)sender
{
    [self.window makeFirstResponder:nil]; // ends the edition of a field
    [self endWithFilter:[self editedFilter]];
}

- (IBAction)cancel:(nullable id)sender
{
    [self endWithFilter:nil];
}

- (nullable NSArray *)tokenField:(NSTokenField *)tokenField completionsForSubstring:(NSString *)substring
                    indexOfToken:(NSInteger)tokenIndex indexOfSelectedItem:(nullable NSInteger *)selectedIndex
{
    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    for (NSString *t in _allTags) {
        if ([t rangeOfString:substring options:NSCaseInsensitiveSearch | NSAnchoredSearch].location != NSNotFound) {
            [matches addObject:t];
        }
    }
    return matches;
}

@end
