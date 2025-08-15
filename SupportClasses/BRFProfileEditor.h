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

@interface BRFProfileEditor : NSWindowController

/// completion will be called on the main thread with the raw extraParams string (e.g. "a=1|b=2") or nil if cancelled
@property (nonatomic, copy) void (^completionHandler)(NSArray *overrideParams);

- (instancetype)initWithProfileName:(NSString *)profileName;
//- (void)showEditor;

@end


NS_ASSUME_NONNULL_END
