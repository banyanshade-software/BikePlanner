//
//  RAGarminFetchSheet.h
//  RideAnalyzer
//
//  The sheet of File ▸ Fetch from Garmin Connect… (#82, R1): the Personal API key of the library (kept in the
//  Keychain, or in the library file if the user checks the box) and what to fetch: the new rides since the last fetch, or all the rides since a date (bulk import).
//  Built in code. Getting the key through the Garmin Connect web session (#79) is still to do: for now the user
//  pastes it.
//

#import <Cocoa/Cocoa.h>


NS_ASSUME_NONNULL_BEGIN

@interface RAGarminFetchSheet : NSWindowController

/// key: the saved key, if any; keepInDocument: the state of the box; lastFetch: shown, and the default choice is
/// "new rides" when there is one
- (instancetype)initWithKey:(nullable NSString *)key keepInDocument:(BOOL)keepInDocument
                  lastFetch:(nullable NSDate *)lastFetch;

/// shows the sheet; completion with the key and the start date (nil: new rides since the last fetch), or
/// cancelled
- (void)beginSheetForWindow:(NSWindow *)window
                 completion:(void (^)(BOOL fetch, NSString *key, BOOL keepInDocument, NSDate * _Nullable since))completion;

// for tests
@property (readonly, nonatomic) NSSecureTextField *keyField;
@property (readonly, nonatomic) NSButton *keepInDocumentButton;
@property (readonly, nonatomic) NSButton *allSinceButton;
@property (readonly, nonatomic) NSDatePicker *sinceDatePicker;
- (IBAction)fetch:(nullable id)sender;
- (IBAction)cancel:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
