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

@class RARide, RAGarminConnect, RAGarminActivity, RAFilter, RASavedFilter, RAEquipment, RAPart, RAClimb;
@protocol RAKeyStore;

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

/// where a library is compared with the place it was last opened or saved from on this user account
typedef NS_ENUM(NSInteger, RALibraryLocation) {
    RALibraryLocationNew,             // never seen on this account, or no file yet
    RALibraryLocationSame,
    RALibraryLocationMoved,           // last seen at another place: moved, or copied in the Finder
    RALibraryLocationOpenElsewhere,   // another open library has the same identifier: a copy
};

@interface RALibraryDocument : NSDocument

@property (readonly, nonatomic) NSArray<RARide *> *rides;
/// stable identifier of the library (its Garmin Connect key in the Keychain goes with it); a copy of the library
/// gets a new one (-becomeCopyCarryingKey:)
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

// Garmin Connect Personal API key of the library. Kept in the Keychain of the user account, one per library
// (two people sharing a Mac account each have their own library, so their own key), or, if the user chooses, in
// the library file itself, obfuscated (to use the library on another Mac; anyone with the file has the key).
/// the key: from the document when it keeps it, else from the key store
@property (readonly, nonatomic, nullable) NSString *garminKey;
@property (readonly, nonatomic) BOOL keepsGarminKeyInDocument;
/// nil or empty: no key. Moves the key between the key store and the document; marks the document edited when
/// the document changes (not undoable: the Keychain is not)
- (void)setGarminKey:(nullable NSString *)key keepInDocument:(BOOL)keepInDocument;
/// the Keychain by default; tests: a RAMemoryKeyStore (nil: back to the Keychain)
@property (class, nonatomic, null_resettable) id<RAKeyStore> keyStore;

// copies of a library: a library opened from another place than the last one (Finder copy, or moved), or while
// another open library has the same identifier, asks whether it is a copy; Save As and Duplicate make a copy for
// the same person. The places are kept in the user defaults (RALibraryLocations: identifier → path).
/// tests: nil for the standard user defaults
@property (class, nonatomic, null_resettable) NSUserDefaults *locationDefaults;
@property (readonly, nonatomic) RALibraryLocation location;
/// the place recorded for this library's identifier, nil if none
@property (readonly, nonatomic, nullable) NSString *recordedPath;
/// records the document's file as the place of its identifier
- (void)recordLocation;
/// a new identifier. carryKey: the key goes with the copy (same person); otherwise the copy has no key and no last
/// fetch date (someone else's Garmin Connect account). Marks the document edited.
- (void)becomeCopyCarryingKey:(BOOL)carryKey;

/// the original file of a ride, nil if missing
- (nullable NSData *)originalDataOfRide:(RARide *)ride;

/// undoable
- (void)renameRide:(RARide *)ride to:(NSString *)name;
/// keeps only a part of the ride's file (seconds from its first point; end 0: to the end), e.g. a computer left
/// running in the car; its figures and stats are computed again; undoable. 0, 0: the whole file again.
- (void)trimRide:(RARide *)ride start:(NSTimeInterval)start end:(NSTimeInterval)end;
/// the figures of a ride (distance, ascent, duration, start, stats) from its file and its trim; any thread
+ (void)updateFiguresOfRide:(RARide *)ride fromData:(NSData *)data;
/// the trim that makes a ride match its Garmin Connect summary when the activity was cut there (its file has the
/// whole recording): start from the activity's start time, end from its duration, else from its distance; NO when
/// the ride already matches (distance within 3 % + 300 m) or nothing can be deduced
+ (BOOL)garminTrimForRide:(RARide *)ride activity:(RAGarminActivity *)activity data:(NSData *)data
                    start:(NSTimeInterval *)start end:(NSTimeInterval *)end;
/// the Garmin Connect corrections of the rides already imported (R1): lists the activities back to the oldest ride
/// from Garmin Connect and trims the rides that are longer than their activity. Completion on the main queue with
/// the number of rides corrected (undoable together). Returns nil when an import is running.
- (nullable NSProgress *)applyGarminCorrections:(RAGarminConnect *)client
                                     completion:(void (^)(NSUInteger corrected, NSError * _Nullable error))completion;
/// undoable; the original file goes with it (and comes back on undo)
- (void)removeRides:(NSArray<RARide *> *)rides;

// devices (R3: filter by device)
/// the device keys of the rides, sorted by label
@property (readonly, nonatomic) NSArray<NSString *> *deviceKeys;
/// the name given by the user, else the name a TCX file gave for this unit, else a default
- (NSString *)labelForDeviceKey:(NSString *)deviceKey;
/// undoable; nil or empty: back to the default
- (void)setLabel:(nullable NSString *)label forDeviceKey:(NSString *)deviceKey;

// trends (R6)
/// the rides whose stats are missing (imported before the stats existed, or computed by an older version)
@property (readonly, nonatomic) NSArray<RARide *> *ridesWithoutStats;
/// computes them in the background from their original files; completion on the main queue
- (void)computeMissingStatsWithCompletion:(void (^)(NSUInteger computed))completion;

// equipment (R13): rider, bikes, parts
/// do not change it directly: changeEquipment:actionName:
@property (readonly, nonatomic) RAEquipment *equipment;
/// one undoable change (the block changes a copy, which then replaces the equipment). When the default bike is set,
/// the rides without bike get it (in the same change). The new rides get the default bike.
- (void)changeEquipment:(void (^)(RAEquipment *equipment))change actionName:(NSString *)actionName;
/// undoable; @"": no bike
- (void)setBikeID:(NSString *)bikeID ofRides:(NSArray<RARide *> *)rides;
/// the parts over their wear limit not warned about yet; marks them warned (saved, not undoable)
- (NSArray<RAPart *> *)takeNewlyWornParts;

// names of the climbs (R7): a name goes to every passage of the same climb (RAClimb isSameClimbAs:)
/// @"" when not named
- (NSString *)nameOfClimb:(RAClimb *)climb;
/// undoable; empty: no name
- (void)setName:(NSString *)name ofClimb:(RAClimb *)climb;

// notes and tags of a ride (R3), undoable
- (void)setNotes:(NSString *)notes ofRide:(RARide *)ride;
/// trimmed, empty ones and duplicates dropped, order kept
- (void)setTags:(NSArray<NSString *> *)tags ofRide:(RARide *)ride;
/// every tag used in the library, sorted
@property (readonly, nonatomic) NSArray<NSString *> *allTags;

// saved filters (R3), undoable
@property (readonly, nonatomic) NSArray<RASavedFilter *> *savedFilters;
- (RASavedFilter *)saveFilter:(RAFilter *)filter name:(NSString *)name;
- (void)removeSavedFilter:(RASavedFilter *)savedFilter;
- (void)renameSavedFilter:(RASavedFilter *)savedFilter to:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
