//
//  BRFProfileEditor.m
//  BikePlanner
//
//  Created by Daniel on 10/08/2025.
//

#import "BRFProfileEditor.h"
#import "BPEnvironment.h"


// BRouter output options, irrelevant for BikePlanner: not shown (#39)
static NSSet<NSString *> *BRFHiddenParams(void)
{
    static NSSet *hidden;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        hidden = [NSSet setWithArray:@[ @"turnInstructionMode", @"turnInstructionCatchingRange",
                                        @"turnInstructionRoundabouts", @"processUnusedTags" ]];
    });
    return hidden;
}

// document view of the scroll view: the parameters start at the top
@interface BRFFlippedView : NSView
@end

static NSLocale *BRFPosixLocale(void)
{
    return [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
}


@interface BRFParam ()
@property (nonatomic, strong, nullable) NSTextField *titleField;
@property (nonatomic, strong, nullable) NSButton *resetButton;
@end

@implementation BRFParam

// "avoid_unsafe" -> "Avoid unsafe", "totalMass" + "Mass (in kg) of…" -> "Total mass (kg)"; names like "S_C_x" are
// kept as they are, unless they have a label in the table
- (NSString *)label
{
    static NSDictionary<NSString *, NSString *> *labels;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        labels = @{ @"downhillcost":   NSLocalizedString(@"Downhill cost", @"BRouter parameter"),
                    @"uphillcost":     NSLocalizedString(@"Uphill cost", @"BRouter parameter"),
                    @"downhillcutoff": NSLocalizedString(@"Downhill cutoff (%)", @"BRouter parameter"),
                    @"uphillcutoff":   NSLocalizedString(@"Uphill cutoff (%)", @"BRouter parameter"),
                    @"S_C_x":          NSLocalizedString(@"Drag area S·Cx (m²)", @"BRouter parameter"),
                    @"C_r":            NSLocalizedString(@"Rolling resistance Cr", @"BRouter parameter") };
    });
    NSString *known = labels[self.name];
    if (known) return known;

    NSString *name = self.name;
    BOOL hasUpper = [name rangeOfCharacterFromSet:[NSCharacterSet uppercaseLetterCharacterSet]].location != NSNotFound;
    NSMutableString *s = [NSMutableString string];
    if ([name containsString:@"_"]) {
        if (hasUpper) return name;
        [s appendString:[name stringByReplacingOccurrencesOfString:@"_" withString:@" "]];
    } else {
        for (NSUInteger i = 0; i < name.length; i++) {
            unichar c = [name characterAtIndex:i];
            NSString *cs = [NSString stringWithCharacters:&c length:1];
            if (i > 0 && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c]) {
                [s appendFormat:@" %@", cs.lowercaseString];
            } else {
                [s appendString:cs];
            }
        }
    }
    if (s.length) {
        [s replaceCharactersInRange:NSMakeRange(0, 1) withString:[s substringToIndex:1].uppercaseString];
    }
    // unit from the description: "… (in km/h) …"
    if (self.help) {
        NSRegularExpression *unitRx = [NSRegularExpression regularExpressionWithPattern:@"\\(in ([^)]+)\\)"
                                                                                options:0 error:nil];
        NSTextCheckingResult *m = [unitRx firstMatchInString:self.help options:0 range:NSMakeRange(0, self.help.length)];
        if (m) {
            NSString *unit = [[self.help substringWithRange:[m rangeAtIndex:1]]
                              stringByReplacingOccurrencesOfString:@"^2" withString:@"²"];
            [s appendFormat:@" (%@)", unit];
        }
    }
    return s;
}

@end

@interface BRFProfileEditor () <NSTextFieldDelegate>
@property (strong) NSStackView *stackView;
@property (strong) NSScrollView *scrollView;
@property (copy) NSString *profileName;
//@property (strong) NSMutableArray<NSDictionary *> *parameters;
@property (strong) NSMutableArray<BRFParam *> *parameters;
@property (strong) NSButton *applyButton;
@property (strong) NSPopUpButton *defaultsMenu;   // Reset to Profile Defaults / Use My Defaults / Save as My Defaults
@property (strong) NSView *defaultsNotice;        // the document's parameters differ from my defaults (#44)
@end

static NSString *const BRFDefaultsKey = @"BPProfileOverrides";



@implementation BRFProfileEditor

+ (nullable NSDictionary<NSString *, NSString *> *)savedOverridesForProfile:(NSString *)profile
                                                               userDefaults:(NSUserDefaults *)userDefaults
{
    id saved = [userDefaults dictionaryForKey:BRFDefaultsKey][profile];
    return [saved isKindOfClass:[NSDictionary class]] ? saved : nil;
}

+ (void)saveOverrides:(NSDictionary<NSString *, NSString *> *)overrides asDefaultsForProfile:(NSString *)profile
         userDefaults:(NSUserDefaults *)userDefaults
{
    NSMutableDictionary *all = [[userDefaults dictionaryForKey:BRFDefaultsKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    all[profile] = [overrides copy];
    [userDefaults setObject:all forKey:BRFDefaultsKey];
}

- (NSUserDefaults *)userDefaults
{
    return _userDefaults ?: [NSUserDefaults standardUserDefaults];
}

- (nullable NSDictionary<NSString *, NSString *> *)savedOverrides
{
    return [[self class] savedOverridesForProfile:self.profileName ?: @"" userDefaults:self.userDefaults];
}

// the document's parameters (initially, after an Apply, an undo or a revert): shown in the controls
- (void)setAppliedOverrides:(NSDictionary<NSString *,NSString *> *)appliedOverrides
{
    _appliedOverrides = [appliedOverrides copy] ?: @{};
    [self showValues:_appliedOverrides];
}


- (void)loadProfileName:(NSString *)profileName;
{
        _profileName = [profileName copy];
        _parameters = [NSMutableArray array];
        _appliedOverrides = @{};
}

 -(void) viewDidLoad
{
    [super viewDidLoad];

    [self initEditorViewIn:self.view];
}

- (void) initEditorViewIn:(NSView *)contentView
{
    self.scrollView = [[NSScrollView alloc] initWithFrame:contentView.bounds];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.drawsBackground = NO;

    // the stack is in a flipped view, so that it starts at the top of the scroll view
    NSView *documentView = [[BRFFlippedView alloc] init];
    documentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stackView = [[NSStackView alloc] init];
    self.stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.stackView.alignment = NSLayoutAttributeLeading;
    self.stackView.spacing = 8;
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [documentView addSubview:self.stackView];
    self.scrollView.documentView = documentView;
    [contentView addSubview:self.scrollView];

    self.defaultsMenu = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
    self.defaultsMenu.accessibilityIdentifier = @"brfDefaults";
    [self.defaultsMenu addItemWithTitle:NSLocalizedString(@"Defaults", @"Params tab, pull-down menu")];
    for (NSArray *item in @[ @[NSLocalizedString(@"Reset to Profile Defaults", @"Params tab"), NSStringFromSelector(@selector(resetAllClicked:))],
                             @[NSLocalizedString(@"Use My Defaults", @"Params tab"), NSStringFromSelector(@selector(useMyDefaults:))],
                             @[NSLocalizedString(@"Save as My Defaults", @"Params tab"), NSStringFromSelector(@selector(saveAsMyDefaults:))] ]) {
        NSMenuItem *mi = [self.defaultsMenu.menu addItemWithTitle:item[0] action:NSSelectorFromString(item[1]) keyEquivalent:@""];
        mi.target = self;
    }
    self.defaultsMenu.toolTip = NSLocalizedString(@"My defaults are the parameters of new documents", @"Params tab");
    self.applyButton = [NSButton buttonWithTitle:NSLocalizedString(@"Apply", @"Params tab")
                                          target:self action:@selector(applyClicked:)];
    self.applyButton.toolTip = NSLocalizedString(@"Recompute the route with these parameters", @"Params tab");
    NSStackView *buttonRow = [NSStackView stackViewWithViews:@[ self.defaultsMenu, [NSView new], self.applyButton ]];

    // notice shown when the document's parameters differ from my defaults
    NSImageView *info = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"info.circle" accessibilityDescription:nil]];
    info.contentTintColor = [NSColor systemBlueColor];
    NSTextField *noticeText = [NSTextField wrappingLabelWithString:
                               NSLocalizedString(@"This route's parameters differ from your defaults.", @"Params tab")];
    noticeText.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    [noticeText setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSButton *useDefaults = [NSButton buttonWithTitle:NSLocalizedString(@"Use My Defaults", @"Params tab")
                                               target:self action:@selector(useMyDefaults:)];
    useDefaults.controlSize = NSControlSizeSmall;
    useDefaults.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    NSStackView *notice = [NSStackView stackViewWithViews:@[ info, noticeText, useDefaults ]];
    notice.distribution = NSStackViewDistributionFill;
    notice.accessibilityIdentifier = @"brfDefaultsNotice";
    notice.hidden = YES;
    self.defaultsNotice = notice;

    NSStackView *buttons = [NSStackView stackViewWithViews:@[ notice, buttonRow ]];
    buttons.orientation = NSUserInterfaceLayoutOrientationVertical;
    buttons.spacing = 6;
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:buttons];
    [notice.widthAnchor constraintEqualToAnchor:buttons.widthAnchor].active = YES;
    [buttonRow.widthAnchor constraintEqualToAnchor:buttons.widthAnchor].active = YES;

    NSClipView *clip = self.scrollView.contentView;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [self.scrollView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:buttons.topAnchor constant:-8],
        [buttons.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:12],
        [buttons.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-12],
        [buttons.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-4],
        [documentView.leadingAnchor constraintEqualToAnchor:clip.leadingAnchor],
        [documentView.trailingAnchor constraintEqualToAnchor:clip.trailingAnchor],
        [documentView.topAnchor constraintEqualToAnchor:clip.topAnchor],
        [self.stackView.leadingAnchor constraintEqualToAnchor:documentView.leadingAnchor constant:12],
        [self.stackView.trailingAnchor constraintEqualToAnchor:documentView.trailingAnchor constant:-16],
        [self.stackView.topAnchor constraintEqualToAnchor:documentView.topAnchor constant:8],
        [self.stackView.bottomAnchor constraintEqualToAnchor:documentView.bottomAnchor constant:-8],
    ]];

    [self showMessage:[NSString stringWithFormat:NSLocalizedString(@"Loading the “%@” profile…", @"Params tab"),
                       self.profileName ?: @""]];
    [self updateState];
    [self fetchProfile];
}

- (void) fetchProfile {
    //NSString *urlStr = [NSString stringWithFormat:@"https://brouter.de/brouter/profiles2/%@.brf", self.profileName];
    NSURL *url = [BPEnvironment brouterProfileURLForName:self.profileName];
    if (!url) return;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 200;
        NSString *profileText = (data && !error && status == 200) ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (profileText) {
                [self parseProfile:profileText];
                [self buildUI];
            } else {
                NSLog(@"BRF profile %@: %@ (HTTP %ld)", url, error.localizedDescription, (long)status);
                [self clearUI];
                [self showMessage:[NSString stringWithFormat:
                                   NSLocalizedString(@"Could not load the “%@” profile (%@).", @"Params tab"),
                                   self.profileName ?: @"",
                                   error ? error.localizedDescription : [NSString stringWithFormat:@"HTTP %ld", (long)status]]];
            }
        });
    }];
    [task resume];
}

#if 1
// user parameters of the global context: "assign <name> [=] <number|true|false> [# %<name>% | <help> | <type>]"
// (BRouter accepts the assignment without "=", #52); when the profile has annotations, the annotated parameters and
// the commented ones (comment = description) are kept, the others are internal variables
- (void)parseProfile:(NSString *)brf
{
    [self.parameters removeAllObjects];
    NSRegularExpression *assignRx = [NSRegularExpression regularExpressionWithPattern:
                                     @"^\\s*assign\\s+(\\w+)\\s*(?:=\\s*)?([\\d\\.\\-]+|true|false)\\s*(?:#(.*))?$"
                                                                              options:NSRegularExpressionCaseInsensitive
                                                                                error:nil];
    NSRegularExpression *annotationRx = [NSRegularExpression regularExpressionWithPattern:
                                         @"^\\s*%(\\w+)%\\s*\\|\\s*(.*?)\\s*\\|\\s*(.*?)\\s*$" options:0 error:nil];
    NSCharacterSet *commentChars = [NSCharacterSet characterSetWithCharactersInString:@"# \t"];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    __block NSString *section = nil;
    __block BOOL global = YES;
    __block BOOL annotations = NO;
    [brf enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"---context:"]) {
            global = [trimmed hasPrefix:@"---context:global"];
            return;
        }
        if (!global) return;
        if ([trimmed hasPrefix:@"#"]) {
            NSString *comment = [trimmed stringByTrimmingCharactersInSet:commentChars];
            if (comment.length && ![comment hasPrefix:@"*"]) section = comment; // "# *** …": profile header
            return;
        }
        NSTextCheckingResult *m = [assignRx firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (!m) return;
        NSString *name = [line substringWithRange:[m rangeAtIndex:1]];
        if ([seen containsObject:name]) return; // later assignments are computations
        [seen addObject:name];
        NSString *val = [line substringWithRange:[m rangeAtIndex:2]];
        BRFParam *p = [BRFParam new];
        p.name = name;
        p.defaultValue = val;
        p.isBoolean = ([val caseInsensitiveCompare:@"true"] == NSOrderedSame || [val caseInsensitiveCompare:@"false"] == NSOrderedSame);
        p.kind = p.isBoolean ? BRFParamBoolean : BRFParamNumber;
        p.section = section;
        NSRange commentRange = [m rangeAtIndex:3];
        if (commentRange.location != NSNotFound) {
            NSString *comment = [line substringWithRange:commentRange];
            NSTextCheckingResult *a = [annotationRx firstMatchInString:comment options:0 range:NSMakeRange(0, comment.length)];
            if (a && [[comment substringWithRange:[a rangeAtIndex:1]] isEqualToString:name]) {
                p.annotated = YES;
                annotations = YES;
                NSString *help = [comment substringWithRange:[a rangeAtIndex:2]];
                p.help = help.length ? help : nil;
                NSString *type = [comment substringWithRange:[a rangeAtIndex:3]];
                if ([type hasPrefix:@"["]) {
                    p.choices = [[self class] choicesFromType:type];
                    if (p.choices.count) p.kind = BRFParamChoice;
                } else if ([type caseInsensitiveCompare:@"boolean"] == NSOrderedSame) {
                    p.kind = BRFParamBoolean;
                }
            } else {
                NSString *help = [comment stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                p.help = help.length ? help : nil; // commented parameter, without type information (#52)
            }
        }
        [self.parameters addObject:p];
    }];
    if (annotations) {
        [self.parameters filterUsingPredicate:[NSPredicate predicateWithFormat:@"annotated == YES OR help != nil"]];
    }
    [self.parameters filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(BRFParam *p, NSDictionary *b) {
        return ![BRFHiddenParams() containsObject:p.name];
    }]];
}

// "[0=none, 1=auto-choose]" -> @[@[@"0", @"none"], @[@"1", @"auto-choose"]]
+ (NSArray<NSArray<NSString *> *> *)choicesFromType:(NSString *)type
{
    NSString *list = [type stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"[] "]];
    NSMutableArray *choices = [NSMutableArray array];
    for (NSString *item in [list componentsSeparatedByString:@","]) {
        NSString *s = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!s.length) continue;
        NSRange eq = [s rangeOfString:@"="];
        if (eq.location == NSNotFound) [choices addObject:@[s, s]];
        else [choices addObject:@[[s substringToIndex:eq.location], [s substringFromIndex:eq.location + 1]]];
    }
    return choices;
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

#pragma mark - values

// values are compared and sent normalized: booleans as 1/0 (#38), numbers without trailing zeros, in POSIX format
+ (NSString *)normalizedValue:(NSString *)value kind:(BRFParamKind)kind
{
    if (kind == BRFParamBoolean) {
        return ([value caseInsensitiveCompare:@"true"] == NSOrderedSame || [value doubleValue] != 0) ? @"1" : @"0";
    }
    if (kind == BRFParamNumber) {
        NSDecimalNumber *n = [NSDecimalNumber decimalNumberWithString:value locale:BRFPosixLocale()];
        if (!isnan(n.doubleValue)) return n.stringValue;
    }
    return value;
}

- (NSString *)defaultValueOf:(BRFParam *)p
{
    return [[self class] normalizedValue:p.defaultValue kind:p.kind];
}

- (NSString *)currentValueOf:(BRFParam *)p
{
    switch (p.kind) {
        case BRFParamBoolean:
            return ((NSSwitch *)p.valueControl).state == NSControlStateValueOn ? @"1" : @"0";
        case BRFParamChoice:
            return ((NSPopUpButton *)p.valueControl).selectedItem.representedObject ?: [self defaultValueOf:p];
        case BRFParamNumber: {
            // while the field is being edited, -stringValue would validate the partial text with the formatter and
            // write it back into the field ("0," -> "0": the decimal separator disappears while typing, #45): read
            // the field editor's text instead
            NSTextField *field = (NSTextField *)p.valueControl;
            NSString *text = field.currentEditor ? field.currentEditor.string : field.stringValue;
            NSNumber *n = [(NSNumberFormatter *)field.formatter numberFromString:text];
            if (!n) return [self defaultValueOf:p]; // being edited, not a number (yet)
            return [[self class] normalizedValue:[n descriptionWithLocale:BRFPosixLocale()] kind:BRFParamNumber];
        }
    }
    return [self defaultValueOf:p];
}

- (void)setValue:(NSString *)value ofParam:(BRFParam *)p
{
    switch (p.kind) {
        case BRFParamBoolean:
            ((NSSwitch *)p.valueControl).state = [value isEqualToString:@"1"] ? NSControlStateValueOn : NSControlStateValueOff;
            break;
        case BRFParamChoice: {
            NSPopUpButton *popup = (NSPopUpButton *)p.valueControl;
            NSInteger i = [popup indexOfItemWithRepresentedObject:value];
            if (i >= 0) [popup selectItemAtIndex:i];
            break;
        }
        case BRFParamNumber:
            ((NSTextField *)p.valueControl).objectValue = [NSDecimalNumber decimalNumberWithString:value locale:BRFPosixLocale()];
            break;
    }
}

// shows these values (name → value), the profile default for the others
- (void)showValues:(NSDictionary<NSString *, NSString *> *)values
{
    for (BRFParam *p in self.parameters) {
        if (!p.valueControl) continue;
        NSString *v = values[p.name];
        [self setValue:v ? [[self class] normalizedValue:v kind:p.kind] : [self defaultValueOf:p] ofParam:p];
    }
    [self updateState];
}

- (NSString *)displayValue:(NSString *)value ofParam:(BRFParam *)p
{
    switch (p.kind) {
        case BRFParamBoolean:
            return [value isEqualToString:@"1"] ? NSLocalizedString(@"on", @"Params tab, default value")
                                                : NSLocalizedString(@"off", @"Params tab, default value");
        case BRFParamChoice:
            for (NSArray<NSString *> *c in p.choices) if ([c[0] isEqualToString:value]) return c[1];
            return value;
        case BRFParamNumber:
            return [(NSNumberFormatter *)((NSTextField *)p.valueControl).formatter
                    stringFromNumber:[NSDecimalNumber decimalNumberWithString:value locale:BRFPosixLocale()]] ?: value;
    }
    return value;
}

// parameters whose value differs from the profile default
- (NSDictionary<NSString *, NSString *> *)currentOverrides
{
    NSMutableDictionary<NSString *, NSString *> *overrides = [NSMutableDictionary dictionary];
    for (BRFParam *p in self.parameters) {
        if (!p.valueControl) continue;
        NSString *value = [self currentValueOf:p];
        if (![value isEqualToString:[self defaultValueOf:p]]) overrides[p.name] = value; // "profile:" added by BRouterClient
    }
    return overrides;
}

// changed parameters are in bold with a reset button; Apply is enabled when the values differ from the last Apply
- (void)updateState
{
    NSDictionary *overrides = [self currentOverrides];
    for (BRFParam *p in self.parameters) {
        BOOL changed = overrides[p.name] != nil;
        p.titleField.font = changed ? [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightSemibold]
                                    : [NSFont systemFontOfSize:NSFont.systemFontSize];
        p.resetButton.hidden = !changed;
    }
    BOOL loaded = self.parameters.firstObject.valueControl != nil;
    self.applyButton.enabled = loaded && ![overrides isEqualToDictionary:self.appliedOverrides];
    NSDictionary *saved = [self savedOverrides];
    self.defaultsNotice.hidden = !(loaded && saved && ![saved isEqualToDictionary:self.appliedOverrides]
                                   && ![saved isEqualToDictionary:overrides]);
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    BOOL loaded = self.parameters.firstObject.valueControl != nil;
    NSDictionary *overrides = [self currentOverrides];
    NSDictionary *saved = [self savedOverrides];
    if (menuItem.action == @selector(resetAllClicked:)) return overrides.count > 0;
    if (menuItem.action == @selector(useMyDefaults:)) return loaded && saved && ![saved isEqualToDictionary:overrides];
    if (menuItem.action == @selector(saveAsMyDefaults:)) return loaded && ![overrides isEqualToDictionary:saved ?: @{}];
    return YES;
}

#pragma mark - UI

- (void)clearUI
{
    for (NSView *v in [self.stackView.arrangedSubviews copy]) {
        [self.stackView removeArrangedSubview:v];
        [v removeFromSuperview];
    }
}

- (void)showMessage:(NSString *)message
{
    NSTextField *label = [NSTextField wrappingLabelWithString:message];
    label.textColor = [NSColor secondaryLabelColor];
    label.accessibilityIdentifier = @"brfMessage";
    [self addFullWidthView:label];
}

- (void)addFullWidthView:(NSView *)view
{
    [self.stackView addArrangedSubview:view];
    [view.widthAnchor constraintEqualToAnchor:self.stackView.widthAnchor].active = YES;
}

- (void) buildUI
{
    [self clearUI];
    if (!self.parameters.count) {
        [self showMessage:[NSString stringWithFormat:NSLocalizedString(@"The “%@” profile has no parameter.", @"Params tab"),
                           self.profileName ?: @""]];
    } else {
        NSTextField *intro = [NSTextField wrappingLabelWithString:[NSString stringWithFormat:
            NSLocalizedString(@"Parameters of the BRouter “%@” profile. Changed values (in bold) are used for the "
                              @"route after Apply.", @"Params tab"), self.profileName ?: @""]];
        intro.textColor = [NSColor secondaryLabelColor];
        intro.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
        [self addFullWidthView:intro];
    }
    NSString *section = nil;
    for (NSUInteger i = 0; i < self.parameters.count; i++) {
        BRFParam *param = self.parameters[i];
        if (param.section && ![param.section isEqualToString:section]) {
            section = param.section;
            NSView *last = self.stackView.arrangedSubviews.lastObject;
            if (last) [self.stackView setCustomSpacing:16 afterView:last];
            NSString *title = [[section substringToIndex:1].uppercaseString stringByAppendingString:[section substringFromIndex:1]];
            NSTextField *header = [NSTextField wrappingLabelWithString:title];
            header.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
            [self addFullWidthView:header];
        }
        [self createRowForParam:param index:i];
    }
    [self showValues:self.appliedOverrides];
}

- (void)createRowForParam:(BRFParam *)param index:(NSUInteger)index
{
    NSString *defaultValue = [self defaultValueOf:param];
    NSControl *control = nil;
    switch (param.kind) {
        case BRFParamBoolean: {
            NSSwitch *sw = [[NSSwitch alloc] init];
            sw.controlSize = NSControlSizeSmall;
            control = sw;
            break;
        }
        case BRFParamChoice: {
            NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
            popup.controlSize = NSControlSizeSmall;
            popup.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
            for (NSArray<NSString *> *c in param.choices) {
                [popup addItemWithTitle:c[1]];
                popup.lastItem.representedObject = c[0];
            }
            control = popup;
            break;
        }
        case BRFParamNumber: {
            NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
            formatter.numberStyle = NSNumberFormatterDecimalStyle;
            formatter.usesGroupingSeparator = NO;
            formatter.maximumFractionDigits = 6;
            formatter.generatesDecimalNumbers = YES;
            NSTextField *field = [NSTextField textFieldWithString:@""];
            field.formatter = formatter;
            field.alignment = NSTextAlignmentRight;
            field.delegate = self;
            [field.widthAnchor constraintEqualToConstant:72].active = YES;
            control = field;
            break;
        }
    }
    control.target = self;
    control.action = @selector(valueChanged:);
    control.accessibilityIdentifier = [@"brf." stringByAppendingString:param.name];
    param.valueControl = control;
    [self setValue:defaultValue ofParam:param];

    NSTextField *title = [NSTextField labelWithString:param.label];
    title.toolTip = param.name;
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    [title setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [title setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    param.titleField = title;
    control.accessibilityLabel = param.label;

    NSString *defaultText = [NSString stringWithFormat:NSLocalizedString(@"Default: %@", @"Params tab"),
                             [self displayValue:defaultValue ofParam:param]];
    NSButton *reset = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"arrow.uturn.backward.circle"
                                                          accessibilityDescription:NSLocalizedString(@"Reset", @"Params tab")]
                                         target:self action:@selector(resetParam:)];
    reset.bordered = NO;
    reset.tag = (NSInteger)index;
    reset.toolTip = [NSString stringWithFormat:NSLocalizedString(@"Reset to the default value (%@)", @"Params tab"),
                     [self displayValue:defaultValue ofParam:param]];
    reset.accessibilityIdentifier = [@"brfReset." stringByAppendingString:param.name];
    param.resetButton = reset;

    NSStackView *line = [NSStackView stackViewWithViews:@[ title, control, reset ]];
    line.spacing = 6;
    line.distribution = NSStackViewDistributionFill; // the title takes the free space: controls on the right
    line.detachesHiddenViews = NO; // the hidden reset button keeps its place: controls stay aligned

    NSString *helpText = param.help ? [NSString stringWithFormat:@"%@ — %@", param.help, defaultText] : defaultText;
    NSTextField *help = [NSTextField wrappingLabelWithString:helpText];
    help.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    help.textColor = [NSColor secondaryLabelColor];
    help.selectable = NO;

    NSStackView *rowView = [NSStackView stackViewWithViews:@[ line, help ]];
    rowView.orientation = NSUserInterfaceLayoutOrientationVertical;
    rowView.alignment = NSLayoutAttributeLeading;
    rowView.spacing = 1;
    [self addFullWidthView:rowView];
    [line.widthAnchor constraintEqualToAnchor:rowView.widthAnchor].active = YES;
    [help.widthAnchor constraintEqualToAnchor:rowView.widthAnchor constant:-28].active = YES;
}

#pragma mark - actions

- (void)valueChanged:(id)sender
{
    [self updateState];
}

- (void)controlTextDidChange:(NSNotification *)notification
{
    [self updateState];
}

- (void)resetParam:(NSButton *)sender
{
    if (sender.tag < 0 || (NSUInteger)sender.tag >= self.parameters.count) return;
    BRFParam *p = self.parameters[(NSUInteger)sender.tag];
    [self setValue:[self defaultValueOf:p] ofParam:p];
    [self updateState];
}

- (void)resetAllClicked:(id)sender
{
    for (BRFParam *p in self.parameters) {
        if (p.valueControl) [self setValue:[self defaultValueOf:p] ofParam:p];
    }
    [self updateState];
}

// my defaults in the controls (sent by Apply)
- (void)useMyDefaults:(id)sender
{
    NSDictionary *saved = [self savedOverrides];
    if (saved) [self showValues:saved];
}

- (void)saveAsMyDefaults:(id)sender
{
    [self.view.window makeFirstResponder:nil]; // ends the editing of a number field
    [[self class] saveOverrides:[self currentOverrides] asDefaultsForProfile:self.profileName ?: @"" userDefaults:self.userDefaults];
    [self updateState];
}

- (void)applyClicked:(id)sender
{
    [self.view.window makeFirstResponder:nil]; // ends the editing of a number field
    NSDictionary<NSString *, NSString *> *overrides = [self currentOverrides];
    self.appliedOverrides = overrides;
    [self updateState];
    if (self.completionHandler) self.completionHandler(overrides);
}

@end


@implementation BRFFlippedView
- (BOOL)isFlipped
{
    return YES;
}
@end
