//
//  RAFilterSheet.h
//  RideAnalyzer
//
//  The sheet that edits the criteria of a filter (#82, R3): period, devices, distance, ascent, tags. The search
//  text stays in the search field of the window. Built in code.
//

#import <Cocoa/Cocoa.h>

@class RAFilter;

NS_ASSUME_NONNULL_BEGIN

@interface RAFilterSheet : NSWindowController

/// devices: device key → label, in the order to show; tags: the tags of the library (completion)
- (instancetype)initWithFilter:(RAFilter *)filter devices:(NSArray<NSArray<NSString *> *> *)devices
                          tags:(NSArray<NSString *> *)tags;
/// completion with the edited filter, or nil when cancelled
- (void)beginSheetForWindow:(NSWindow *)window completion:(void (^)(RAFilter * _Nullable filter))completion;

// for tests
- (RAFilter *)editedFilter;
@property (readonly, nonatomic) NSButton *fromCheckbox, *toCheckbox;
@property (readonly, nonatomic) NSDatePicker *fromPicker, *toPicker;
@property (readonly, nonatomic) NSTextField *minDistanceField, *maxDistanceField, *minAscentField;
@property (readonly, nonatomic) NSArray<NSButton *> *deviceCheckboxes;
@property (readonly, nonatomic) NSTokenField *tagsField;
- (IBAction)apply:(nullable id)sender;
- (IBAction)cancel:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
