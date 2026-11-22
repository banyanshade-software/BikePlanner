//
//  RAPowerSettingsWindowController.h
//  RideAnalyzer
//
//  The parameters of the estimated power (#82, R11, #94): by group (drivetrain, rolling resistance, speed and
//  cadence of the file, masses, air drag by position), each with its value — empty for the default —, unit,
//  default and what it does; Restore Defaults; the surface factors (Surface Factors…); and the calibration on the
//  rides that have a power meter (RACalibration), whose result can be applied (Crr multiplier, CdA of the bike).
//  Changes go to the equipment of the library (undoable) and apply at once; the freewheeling rule computes the
//  stats again. From the Equipment window (Power Estimate…). Built in code.
//

#import <Cocoa/Cocoa.h>

@class RALibraryDocument, RACalibrationResult;

NS_ASSUME_NONNULL_BEGIN

@interface RAPowerSettingsWindowController : NSWindowController

- (instancetype)initWithLibrary:(RALibraryDocument *)library;

/// nil: back to the default; bounded
- (void)setValue:(nullable NSNumber *)value ofParameter:(NSString *)key;
- (IBAction)restoreDefaults:(nullable id)sender;
/// calibrates on the rides of the library with a power meter
- (IBAction)calibrate:(nullable id)sender;
/// the Crr multiplier × the result's, and the result's CdA for its bike (one undoable change)
- (void)applyCalibration:(RACalibrationResult *)result;
/// opens the surface factors (RASurfaceFactorsWindowController)
@property (copy, nonatomic, nullable) void (^surfaceFactorsHandler)(void);

// for tests
@property (readonly, nonatomic) NSDictionary<NSString *, NSControl *> *controls;
@property (readonly, nonatomic) NSArray<RACalibrationResult *> *calibrationResults;

@end

NS_ASSUME_NONNULL_END
