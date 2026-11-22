//
//  RAPowerSettingsWindowController.m
//  RideAnalyzer
//

#import "RAPowerSettingsWindowController.h"
#import "RAPowerSettings.h"
#import "RACalibration.h"
#import "RAEquipment.h"
#import "RALibraryDocument.h"

// a flipped document view: the content starts at the top
@interface RAPowerSettingsFlippedView : NSView
@end

@implementation RAPowerSettingsFlippedView
- (BOOL)isFlipped { return YES; }
@end

@implementation RAPowerSettingsWindowController
{
    __weak RALibraryDocument *_library;
    NSNumberFormatter *_number;
    NSMutableDictionary<NSString *, NSControl *> *_controls;
    NSStackView *_calibrationRows;
    NSTextField *_calibrationStatus;
    NSArray<RACalibrationResult *> *_calibrationResults;
}

- (instancetype)initWithLibrary:(RALibraryDocument *)library
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 860, 720)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
          backing:NSBackingStoreBuffered defer:YES];
    window.title = NSLocalizedString(@"Power Estimate", @"power settings window");
    window.identifier = @"powerSettings";
    window.minSize = NSMakeSize(700, 480);
    self = [super initWithWindow:window];
    if (!self) return nil;
    _library = library;
    _number = [[NSNumberFormatter alloc] init];
    _number.numberStyle = NSNumberFormatterDecimalStyle;
    _number.maximumFractionDigits = 3;
    _number.lenient = YES;
    _controls = [NSMutableDictionary dictionary];
    _calibrationResults = @[];
    [self buildContent];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryDidChange:)
                                                 name:RALibraryDidChangeNotification object:library];
    [self reload];
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSDictionary<NSString *, NSControl *> *)controls
{
    return _controls;
}

- (NSArray<RACalibrationResult *> *)calibrationResults
{
    return _calibrationResults;
}

- (NSTextField *)small:(NSString *)text
{
    NSTextField *t = [NSTextField wrappingLabelWithString:text];
    t.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    t.textColor = [NSColor secondaryLabelColor];
    return t;
}

- (void)buildContent
{
    NSMutableArray<NSView *> *views = [NSMutableArray array];
    [views addObject:[NSTextField wrappingLabelWithString:NSLocalizedString(
        @"Without a power meter, the power is computed from the speed, the slope and the accelerations against gravity, "
        @"rolling resistance, air drag and the inertia of the wheels, with these parameters, the equipment (rider and "
        @"bike weights, tyres and their pressure, position) and the roads (surfaces). Empty: the default. A change "
        @"applies at once to every ride.", @"power settings")]];
    for (NSString *group in [RAPowerSettings groups]) {
        NSTextField *title = [NSTextField labelWithString:[RAPowerSettings nameOfGroup:group]];
        title.font = [NSFont boldSystemFontOfSize:13];
        [views addObject:title];
        NSGridView *grid = [NSGridView gridViewWithNumberOfColumns:5 rows:0];
        grid.columnSpacing = 8;
        grid.rowSpacing = 4;
        for (NSString *key in [RAPowerSettings parametersOfGroup:group]) {
            NSControl *control;
            if ([RAPowerSettings isSwitch:key]) {
                control = [NSButton checkboxWithTitle:@"" target:self action:@selector(edited:)];
            } else {
                NSTextField *f = [NSTextField textFieldWithString:@""];
                f.alignment = NSTextAlignmentRight;
                f.target = self;
                f.action = @selector(edited:);
                [f.widthAnchor constraintEqualToConstant:64].active = YES;
                control = f;
            }
            control.identifier = [@"power." stringByAppendingString:key];
            _controls[key] = control;
            NSString *def = [RAPowerSettings isSwitch:key]
                ? ([RAPowerSettings defaultOfParameter:key] >= 0.5 ? NSLocalizedString(@"on", @"power settings")
                                                                    : NSLocalizedString(@"off", @"power settings"))
                : [_number stringFromNumber:@([RAPowerSettings defaultOfParameter:key])] ?: @"";
            NSTextField *explanation = [self small:[RAPowerSettings explanationOfParameter:key]];
            [explanation.widthAnchor constraintEqualToConstant:360].active = YES;
            [grid addRowWithViews:@[ [NSTextField labelWithString:[RAPowerSettings nameOfParameter:key]], control,
                                     [NSTextField labelWithString:[RAPowerSettings unitOfParameter:key]],
                                     [self small:[NSString stringWithFormat:NSLocalizedString(@"default %@", @"power settings"), def]],
                                     explanation ]];
        }
        [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
        for (NSInteger r = 0; r < grid.numberOfRows; r++) [grid rowAtIndex:r].yPlacement = NSGridCellPlacementCenter;
        [views addObject:grid];
    }
    NSButton *restore = [NSButton buttonWithTitle:NSLocalizedString(@"Restore Defaults", @"power settings") target:self
                                           action:@selector(restoreDefaults:)];
    restore.identifier = @"powerRestore";
    NSButton *surfaces = [NSButton buttonWithTitle:NSLocalizedString(@"Surface Factors…", @"power settings") target:self
                                            action:@selector(showSurfaceFactors:)];
    surfaces.identifier = @"powerSurfaceFactors";
    [views addObject:[NSStackView stackViewWithViews:@[ restore, surfaces ]]];

    NSTextField *calTitle = [NSTextField labelWithString:NSLocalizedString(@"Calibration on the rides with a power meter",
                                                                           @"power settings")];
    calTitle.font = [NSFont boldSystemFontOfSize:13];
    [views addObject:calTitle];
    [views addObject:[self small:NSLocalizedString(
        @"Finds, per bike, the Crr multiplier and the CdA that make the estimate match the measured power on the flat "
        @"and the climbs of those rides (least squares on their figures; the descents are left out).", @"power settings")]];
    NSButton *calibrate = [NSButton buttonWithTitle:NSLocalizedString(@"Calibrate", @"power settings") target:self
                                             action:@selector(calibrate:)];
    calibrate.identifier = @"powerCalibrate";
    [views addObject:calibrate];
    _calibrationStatus = [self small:@""];
    _calibrationStatus.identifier = @"powerCalibrationStatus";
    [views addObject:_calibrationStatus];
    _calibrationRows = [NSStackView stackViewWithViews:@[]];
    _calibrationRows.orientation = NSUserInterfaceLayoutOrientationVertical;
    _calibrationRows.alignment = NSLayoutAttributeLeading;
    [views addObject:_calibrationRows];

    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.edgeInsets = NSEdgeInsetsMake(14, 16, 14, 16);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *document = [[RAPowerSettingsFlippedView alloc] init];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:stack];
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.documentView = document;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:document.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:document.bottomAnchor],
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor] ]];
    self.window.contentView = scroll;
}

- (void)libraryDidChange:(NSNotification *)n
{
    [self reload];
}

- (void)reload
{
    NSDictionary<NSString *, NSNumber *> *changed = _library.equipment.powerParameters ?: @{};
    for (NSString *key in _controls) {
        NSControl *c = _controls[key];
        if ([c isKindOfClass:[NSButton class]]) {
            double v = changed[key] != nil ? changed[key].doubleValue : [RAPowerSettings defaultOfParameter:key];
            ((NSButton *)c).state = v >= 0.5 ? NSControlStateValueOn : NSControlStateValueOff;
        } else {
            NSTextField *f = (NSTextField *)c;
            if (f.currentEditor) continue;
            f.stringValue = changed[key] != nil ? [_number stringFromNumber:changed[key]] ?: @"" : @"";
            f.placeholderString = [_number stringFromNumber:@([RAPowerSettings defaultOfParameter:key])];
        }
    }
}

- (void)edited:(NSControl *)sender
{
    NSString *key = [sender.identifier substringFromIndex:@"power.".length];
    if ([sender isKindOfClass:[NSButton class]]) {
        [self setValue:@(((NSButton *)sender).state == NSControlStateValueOn ? 1 : 0) ofParameter:key];
        return;
    }
    NSString *s = [sender.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSNumber *n = s.length ? ([_number numberFromString:s] ?: @([[s stringByReplacingOccurrencesOfString:@"," withString:@"."] doubleValue]))
                           : nil;
    [self setValue:n ofParameter:key];
}

- (void)setValue:(nullable NSNumber *)value ofParameter:(NSString *)key
{
    RALibraryDocument *library = _library;
    if (!library || ![[RAPowerSettings allParameters] containsObject:key]) return;
    [library changeEquipment:^(RAEquipment *e) {
        NSMutableDictionary<NSString *, NSNumber *> *d = [e.powerParameters mutableCopy];
        if (value != nil && isfinite(value.doubleValue)) {
            d[key] = @(MIN(MAX(value.doubleValue, [RAPowerSettings minimumOfParameter:key]), [RAPowerSettings maximumOfParameter:key]));
        } else {
            [d removeObjectForKey:key];
        }
        e.powerParameters = d;
    } actionName:NSLocalizedString(@"Power Estimate Parameter", @"undo action name")];
    [self reload];
    // the freewheeling rule is in the stats: computed again in the background
    if ([RAPowerSettings changesStats:key]) [library computeMissingStatsWithCompletion:^(NSUInteger n) {}];
}

- (IBAction)restoreDefaults:(nullable id)sender
{
    RALibraryDocument *library = _library;
    BOOL stats = NO;
    for (NSString *k in library.equipment.powerParameters) stats = stats || [RAPowerSettings changesStats:k];
    [library changeEquipment:^(RAEquipment *e) { e.powerParameters = @{}; }
                  actionName:NSLocalizedString(@"Restore Power Estimate Parameters", @"undo action name")];
    [self reload];
    if (stats) [library computeMissingStatsWithCompletion:^(NSUInteger n) {}];
}

- (IBAction)showSurfaceFactors:(nullable id)sender
{
    if (self.surfaceFactorsHandler) self.surfaceFactorsHandler();
}

#pragma mark - calibration

- (IBAction)calibrate:(nullable id)sender
{
    RALibraryDocument *library = _library;
    if (!library) return;
    _calibrationResults = [RACalibration calibrateRides:library.rides equipment:library.equipment];
    for (NSView *v in _calibrationRows.arrangedSubviews.copy) [v removeFromSuperview];
    if (_calibrationResults.count == 0) {
        _calibrationStatus.stringValue = NSLocalizedString(@"No ride with a power meter in this library: the estimate "
                                                           @"cannot be checked against a measure.", @"calibration");
        return;
    }
    _calibrationStatus.stringValue = @"";
    for (RACalibrationResult *r in _calibrationResults) {
        NSString *text = [NSString localizedStringWithFormat:NSLocalizedString(
            @"%@ — %lu rides, %lu stretches: measured %.0f W, estimated %.0f W (error %.0f W)", @"calibration"),
            r.bikeName, (unsigned long)r.rideCount, (unsigned long)r.sampleCount, r.measured, r.estimatedBefore, r.errorBefore];
        if (r.valid) {
            text = [text stringByAppendingFormat:@"\n%@", [NSString localizedStringWithFormat:NSLocalizedString(
                @"Fit: Crr × %.2f, CdA %.3f m² → estimated %.0f W (error %.0f W)", @"calibration"),
                r.rollingFactor, r.cdA, r.estimatedAfter, r.errorAfter]];
        } else {
            text = [text stringByAppendingFormat:@"\n%@", r.note];
        }
        NSTextField *label = [NSTextField wrappingLabelWithString:text];
        [label.widthAnchor constraintLessThanOrEqualToConstant:620].active = YES;
        NSMutableArray<NSView *> *row = [NSMutableArray arrayWithObject:label];
        if (r.valid) {
            NSButton *apply = [NSButton buttonWithTitle:NSLocalizedString(@"Apply", @"calibration") target:self
                                                 action:@selector(applyButton:)];
            apply.tag = (NSInteger)[_calibrationResults indexOfObject:r];
            apply.identifier = [@"calibrationApply." stringByAppendingString:r.bikeID];
            [row addObject:apply];
        }
        [_calibrationRows addArrangedSubview:[NSStackView stackViewWithViews:row]];
    }
}

- (void)applyButton:(NSButton *)sender
{
    if (sender.tag >= 0 && (NSUInteger)sender.tag < _calibrationResults.count) {
        [self applyCalibration:_calibrationResults[(NSUInteger)sender.tag]];
    }
}

- (void)applyCalibration:(RACalibrationResult *)result
{
    if (!result.valid) return;
    RALibraryDocument *library = _library;
    double scale = library.equipment.powerSettings.rollingScale * result.rollingFactor;
    [library changeEquipment:^(RAEquipment *e) {
        NSMutableDictionary<NSString *, NSNumber *> *d = [e.powerParameters mutableCopy];
        d[RAPowerRollingScale] = @(MIN(MAX(scale, [RAPowerSettings minimumOfParameter:RAPowerRollingScale]),
                                       [RAPowerSettings maximumOfParameter:RAPowerRollingScale]));
        e.powerParameters = d;
        [e bikeWithID:result.bikeID].cdA = result.cdA;
    } actionName:NSLocalizedString(@"Apply Calibration", @"undo action name")];
    [self reload];
    _calibrationStatus.stringValue = [NSString localizedStringWithFormat:NSLocalizedString(
        @"Applied: Crr multiplier %.2f, CdA %.3f m² for %@ (Edit ▸ Undo goes back).", @"calibration"),
        scale, result.cdA, result.bikeName];
}

@end
