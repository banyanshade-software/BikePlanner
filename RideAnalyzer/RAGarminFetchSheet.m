//
//  RAGarminFetchSheet.m
//  RideAnalyzer
//

#import "RAGarminFetchSheet.h"

@implementation RAGarminFetchSheet
{
    NSButton *_newButton;
    NSButton *_fetchButton;
    void (^_completion)(BOOL, NSString *, BOOL, NSDate *);
}

- (instancetype)initWithKey:(nullable NSString *)key keepInDocument:(BOOL)keepInDocument
                  lastFetch:(nullable NSDate *)lastFetch
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 300)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    self = [super initWithWindow:window];
    if (self) {
        NSTextField *title = [NSTextField labelWithString:NSLocalizedString(@"Fetch from Garmin Connect", @"Garmin sheet")];
        title.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize + 1];
        NSTextField *help = [NSTextField wrappingLabelWithString:NSLocalizedString(
            @"Create a Personal API key in Garmin Connect (Settings ▸ Personal API token) and paste it here. "
            @"It is kept in your Keychain, for this library only, unless you keep it in the library file.",
            @"Garmin sheet")];
        help.textColor = [NSColor secondaryLabelColor];
        _keyField = [[NSSecureTextField alloc] init];
        _keyField.placeholderString = NSLocalizedString(@"Personal API key", @"Garmin sheet");
        _keyField.stringValue = key ?: @"";
        _keyField.identifier = @"garminKey";
        [_keyField.widthAnchor constraintGreaterThanOrEqualToConstant:420].active = YES;
        _keepInDocumentButton = [NSButton checkboxWithTitle:NSLocalizedString(
            @"Keep the key in the library file, to use it on another Mac", @"Garmin sheet") target:nil action:NULL];
        _keepInDocumentButton.state = keepInDocument ? NSControlStateValueOn : NSControlStateValueOff;
        _keepInDocumentButton.identifier = @"garminKeepKey";
        _keepInDocumentButton.toolTip = NSLocalizedString(
            @"The key is then hidden in the file, not encrypted: anyone who has the file can use it.", @"Garmin sheet");

        NSString *newTitle = NSLocalizedString(@"New rides only", @"Garmin sheet");
        if (lastFetch) {
            NSString *when = [NSDateFormatter localizedStringFromDate:lastFetch dateStyle:NSDateFormatterMediumStyle
                                                            timeStyle:NSDateFormatterShortStyle];
            newTitle = [NSString stringWithFormat:NSLocalizedString(@"New rides only (last fetch: %@)", @"Garmin sheet"), when];
        }
        _newButton = [NSButton radioButtonWithTitle:newTitle target:self action:@selector(choiceChanged:)];
        _newButton.identifier = @"garminNewRides";
        _allSinceButton = [NSButton radioButtonWithTitle:NSLocalizedString(@"All rides since:", @"Garmin sheet")
                                                  target:self action:@selector(choiceChanged:)];
        _allSinceButton.identifier = @"garminAllSince";
        _sinceDatePicker = [[NSDatePicker alloc] init];
        _sinceDatePicker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
        _sinceDatePicker.datePickerElements = NSDatePickerElementFlagYearMonthDay;
        _sinceDatePicker.dateValue = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitYear value:-1
                                                                             toDate:[NSDate date] options:0] ?: [NSDate date];
        _sinceDatePicker.identifier = @"garminSince";
        NSStackView *since = [NSStackView stackViewWithViews:@[ _allSinceButton, _sinceDatePicker ]];
        (lastFetch ? _newButton : _allSinceButton).state = NSControlStateValueOn;

        NSButton *cancel = [NSButton buttonWithTitle:NSLocalizedString(@"Cancel", @"button") target:self action:@selector(cancel:)];
        cancel.keyEquivalent = @"\033";
        _fetchButton = [NSButton buttonWithTitle:NSLocalizedString(@"Fetch", @"button") target:self action:@selector(fetch:)];
        _fetchButton.keyEquivalent = @"\r";
        _fetchButton.identifier = @"garminFetch";
        NSStackView *buttons = [NSStackView stackViewWithViews:@[ cancel, _fetchButton ]];

        NSStackView *content = [NSStackView stackViewWithViews:@[ title, help, _keyField, _keepInDocumentButton, _newButton, since, buttons ]];
        content.orientation = NSUserInterfaceLayoutOrientationVertical;
        content.alignment = NSLayoutAttributeLeading;
        content.spacing = 12;
        content.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
        [content setCustomSpacing:20 afterView:since];
        [content setCustomSpacing:20 afterView:_keepInDocumentButton];
        [help.widthAnchor constraintEqualToConstant:420].active = YES;
        [buttons.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20].active = YES;
        window.contentView = content;
        [self choiceChanged:self];
    }
    return self;
}

- (void)choiceChanged:(id)sender
{
    if (sender == _newButton) _allSinceButton.state = NSControlStateValueOff;
    if (sender == _allSinceButton) _newButton.state = NSControlStateValueOff;
    _sinceDatePicker.enabled = _allSinceButton.state == NSControlStateValueOn;
}

- (void)beginSheetForWindow:(NSWindow *)window
                 completion:(void (^)(BOOL fetch, NSString *key, BOOL keepInDocument, NSDate * _Nullable since))completion
{
    _completion = [completion copy];
    [window beginSheet:self.window completionHandler:nil];
}

- (void)endWithFetch:(BOOL)fetch
{
    void (^completion)(BOOL, NSString *, BOOL, NSDate *) = _completion;
    _completion = nil;
    NSString *key = [_keyField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSDate *since = _allSinceButton.state == NSControlStateValueOn
        ? [[NSCalendar currentCalendar] startOfDayForDate:_sinceDatePicker.dateValue] : nil;
    if (self.window.sheetParent) [self.window.sheetParent endSheet:self.window];
    BOOL keep = _keepInDocumentButton.state == NSControlStateValueOn;
    if (completion) completion(fetch, key, keep, since);
}

- (IBAction)fetch:(nullable id)sender
{
    NSString *key = [_keyField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (key.length == 0) {
        NSBeep();
        [self.window makeFirstResponder:_keyField];
        return;
    }
    [self endWithFetch:YES];
}

- (IBAction)cancel:(nullable id)sender
{
    [self endWithFetch:NO];
}

@end
