//
//  BRFProfileEditor.h
//  BikePlanner
//
//  Created by Daniel on 10/08/2025.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface BRFParam : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *defaultValue;
@property (nonatomic, assign) BOOL isBoolean; // true if 0/1
@property (nonatomic, strong) NSButton *overrideButton;
@property (nonatomic, strong) NSView *valueControl; // NSTextField or NSSlider or NSButton
@end

@interface BRFProfileEditor : NSViewController

/// called on the main thread by Done/Save with the overridden parameters (name → value, without the "profile:"
/// prefix); empty when no parameter is overridden
@property (nonatomic, copy) void (^completionHandler)(NSDictionary<NSString *, NSString *> *overrideParams);

- (void)loadProfileName:(NSString *)profileName;
//- (void)showEditor;

@end


NS_ASSUME_NONNULL_END
