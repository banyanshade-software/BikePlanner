//
//  BPGarminConnectController.h
//  BikePlanner
//
//  File ▸ Send to Garmin Connect… (#79): a sheet with the Garmin Connect web site in a web view. The user logs in
//  there (the app never sees the credentials; the session is kept in the app's website data); then the app does what
//  the user would do by hand: on the courses page, "Importer"; it gives the GPX to the file chooser of the popup;
//  "Mise en route"; the activity type (from the surfaces); "Enregistrer". It stops on the last popup (name, privacy):
//  the user saves, then sends the course to the device. One course per file (stages, #69), one after the other.
//  A step that is not recognized (the site changed): the page stays as is and the status line says what to do by
//  hand; the automation goes on when the page moves on.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "BPGarminCourse.h"
#import "BPGarminCredentials.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BPGarminStep) {
    BPGarminStepLoading,
    BPGarminStepLogin,        // waiting for the user to log in
    BPGarminStepCourses,      // the courses page: "Importer"
    BPGarminStepImportPopup,  // the import popup: the file chooser
    BPGarminStepStart,        // the file chosen: "Mise en route"
    BPGarminStepActivity,     // the editor: the activity type
    BPGarminStepName,         // the editor: "Enregistrer"
    BPGarminStepUserSave,     // the last popup: left to the user
    BPGarminStepDone,
};

typedef NS_ENUM(NSInteger, BPGarminRemember) {
    BPGarminRememberYes,
    BPGarminRememberNotNow,
    BPGarminRememberNever,   // never for this account
};

@interface BPGarminConnectController : NSWindowController <WKNavigationDelegate, WKUIDelegate>

/// the login kept by BikePlanner (owner's choice 2026-11-19): typed by the user on the Garmin login page, kept in the
/// Keychain if the user agrees, filled in the page the next times (the user clicks "Se connecter"). Default: the login
/// Keychain; tests: in memory
@property (strong, nonatomic) id<BPGarminCredentialStore> credentials;
/// asks whether to remember the login typed (default: an alert on the sheet; tests: a block that answers)
@property (copy, nullable) void (^rememberPrompt)(NSString *account, void (^answer)(BPGarminRemember choice));

/// files: the GPX of the courses, in order; the website data of the app (the Garmin session) is kept
- (instancetype)initWithFiles:(NSArray<NSURL *> *)files activity:(BPGarminActivity)activity;
/// tests: fake pages served by a scheme handler, with a non persistent data store
- (instancetype)initWithFiles:(NSArray<NSURL *> *)files activity:(BPGarminActivity)activity
                schemeHandler:(nullable id<WKURLSchemeHandler>)handler forScheme:(nullable NSString *)scheme;

/// loads the courses page of Garmin Connect (BPEnvironment garminConnectURL) and runs the automation
- (void)start;
- (IBAction)logOut:(nullable id)sender;
/// called when the sheet is closed (by the Close button)
@property (copy, nullable) void (^closeHandler)(void);

@property (readonly, nonatomic) WKWebView *webView;
@property (readonly, nonatomic) BPGarminStep step;
@property (readonly, nonatomic) NSUInteger fileIndex;
@property (readonly, nonatomic) NSString *statusText;
/// seconds before a step not recognized shows what to do by hand (default 20)
@property (nonatomic) NSTimeInterval stepTimeout;
/// the native login fields (macOS Passwords AutoFill), shown on the login step; their button fills the Garmin page
@property (readonly, nonatomic) BOOL loginBarShown;
- (IBAction)fillLoginFromFields:(id)sender;

/// Report a Problem… (owner's choice 2026-11-23): a popup with the report of the session, copied to the clipboard
- (IBAction)reportProblem:(id)sender;
/// the report: app and macOS versions, step, page path, the button texts of the page, the lines of the session; never
/// the login
- (void)reportTextWithCompletion:(void (^)(NSString *text))completion;
/// tests: a private pasteboard (default: the general one)
@property (strong, nullable) NSPasteboard *reportPasteboard;
- (void)copyReportText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
