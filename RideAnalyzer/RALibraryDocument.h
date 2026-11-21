//
//  RALibraryDocument.h
//  RideAnalyzer
//
//  A ride library (#82, R15): one document per person, a package `.ridelib` holding
//    Library.plist   the rides (RARide property lists) and the library's settings (identifier, device names,
//                    last Garmin Connect fetch)
//    Rides/          the original files (FIT, GPX, TCX), kept as imported (R1, R2)
//
//  Imports (R1, R2) parse the files off the main thread, report an NSProgress that can be cancelled, then add the
//  new rides in one undoable action; a cancelled import keeps what was read (importing again resumes: duplicates
//  are skipped).
//

#import <Cocoa/Cocoa.h>

@class RARide, RAGarminConnect;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const RALibraryDocumentType;              // UTI of a library
extern NSNotificationName const RALibraryDidChangeNotification;

typedef NS_ENUM(NSInteger, RAImportStatus) {
    RAImportStatusImported,
    RAImportStatusDuplicate,      // same file, same Garmin activity, or same ride (start and distance) already there
    RAImportStatusUnreadable,
};

/// the outcome of an import (R2) or of a fetch from Garmin Connect (R1)
@interface RAImportSummary : NSObject
@property (nonatomic) NSUInteger imported;
@property (nonatomic) NSUInteger duplicates;
@property (nonatomic) NSUInteger unreadable;    // files that are not tracks, or activities that could not be fetched
@property (nonatomic) BOOL cancelled;
@end

@interface RALibraryDocument : NSDocument

@property (readonly, nonatomic) NSArray<RARide *> *rides;
/// stable identifier of the library (its Garmin Connect key in the Keychain goes with it)
@property (readonly, nonatomic) NSString *libraryID;
/// end of the last complete fetch from Garmin Connect (R1), nil before the first one
@property (readonly, nonatomic, nullable) NSDate *garminLastFetch;
/// an import or a fetch is running (one at a time)
@property (readonly, nonatomic, getter=isImporting) BOOL importing;

/// a ride read from a file, not yet in a library: figures, format, content hash, device, sport. Any thread.
/// nil (and an error) for a file that is not a track or has fewer than 2 points
+ (nullable RARide *)rideFromData:(NSData *)data fileName:(NSString *)fileName error:(NSError * _Nullable *)error;
/// the files to import from files and folders (folders: their FIT / GPX / TCX files, subfolders included)
+ (NSArray<NSURL *> *)importableFilesAtURLs:(NSArray<NSURL *> *)urls;
/// the activity folders of the bike computers or watches connected as a disk (R2): <volume>/Garmin/Activity.
/// volumes: nil for the mounted volumes. Recent devices that connect with MTP do not show as a disk.
+ (NSArray<NSURL *> *)deviceActivityFoldersInVolumes:(nullable NSArray<NSURL *> *)volumes;

/// the ride of the library that is the same as this one (same file, same Garmin activity, or same ride), nil if new
- (nullable RARide *)existingRideMatching:(RARide *)candidate;

/// imports one file synchronously; undoable
- (RAImportStatus)importData:(NSData *)data fileName:(NSString *)fileName error:(NSError * _Nullable *)error;
/// several files or folders, read in the background; one undoable action; completion on the main queue.
/// Returns nil when an import is already running.
- (nullable NSProgress *)importFilesAtURLs:(NSArray<NSURL *> *)urls
                                completion:(void (^)(RAImportSummary *summary))completion;
/// the new outdoor cycling activities of Garmin Connect (R1): since the last fetch (the activities already in the
/// library stop the listing), or all those since `since` (bulk import, e.g. a whole history). Completion on the
/// main queue, with an error when the listing failed (nothing imported). Returns nil when an import is running.
- (nullable NSProgress *)fetchFromGarmin:(RAGarminConnect *)client since:(nullable NSDate *)since
                              completion:(void (^)(RAImportSummary * _Nullable summary, NSError * _Nullable error))completion;

/// the original file of a ride, nil if missing
- (nullable NSData *)originalDataOfRide:(RARide *)ride;

/// undoable
- (void)renameRide:(RARide *)ride to:(NSString *)name;
/// undoable; the original file goes with it (and comes back on undo)
- (void)removeRides:(NSArray<RARide *> *)rides;

// devices (R3: filter by device)
/// the device keys of the rides, sorted by label
@property (readonly, nonatomic) NSArray<NSString *> *deviceKeys;
/// the name given by the user, else the name a TCX file gave for this unit, else a default
- (NSString *)labelForDeviceKey:(NSString *)deviceKey;
/// undoable; nil or empty: back to the default
- (void)setLabel:(nullable NSString *)label forDeviceKey:(NSString *)deviceKey;

@end

NS_ASSUME_NONNULL_END
