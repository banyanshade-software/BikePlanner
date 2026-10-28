//
//  BRFProfileEditor.h
//  BikePlanner
//
//  Created by Daniel on 10/08/2025.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BRFParamKind) {
    BRFParamNumber,
    BRFParamBoolean,
    BRFParamChoice,
};

// a user parameter of a BRouter profile: "assign <name> = <value>", in the global context, with the annotation
// "# %<name>% | <description> | boolean|number|[0=a, 1=b…]" used by brouter-web (#39)
@interface BRFParam : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *defaultValue;     // as written in the profile ("60", "1.5", "true"…)
@property (nonatomic, assign) BOOL isBoolean;           // true/false (sent as 1/0, #38)
@property (nonatomic, assign) BRFParamKind kind;
@property (nonatomic, copy, nullable) NSString *help;   // description of the annotation
@property (nonatomic, copy, nullable) NSString *section; // last "# …" comment line before the parameter
@property (nonatomic, copy, nullable) NSArray<NSArray<NSString *> *> *choices; // BRFParamChoice: @[value, title]
@property (nonatomic, assign) BOOL annotated;
@property (nonatomic, readonly) NSString *label;        // readable name, with the unit of the description
@property (nonatomic, strong, nullable) NSControl *valueControl; // NSSwitch, NSTextField or NSPopUpButton
@end

@interface BRFProfileEditor : NSViewController

/// called on the main thread by Apply with the overridden parameters (name → value, without the "profile:"
/// prefix): the ones whose value differs from the profile default; empty when there is none
@property (nonatomic, copy) void (^completionHandler)(NSDictionary<NSString *, NSString *> *overrideParams);

- (void)loadProfileName:(NSString *)profileName;
//- (void)showEditor;

@end


NS_ASSUME_NONNULL_END
