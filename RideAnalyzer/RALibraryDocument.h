//
//  RALibraryDocument.h
//  RideAnalyzer
//
//  A ride library (#82, R15): one document per person, a package `.ridelib` holding
//    Library.plist   the rides (RARide property lists) and the settings
//    Rides/          the original files (FIT, GPX, TCX), kept as imported (R1, R2)
//

#import <Cocoa/Cocoa.h>

@class RARide;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const RALibraryDocumentType;              // UTI of a library
extern NSNotificationName const RALibraryDidChangeNotification;

typedef NS_ENUM(NSInteger, RAImportStatus) {
    RAImportStatusImported,
    RAImportStatusDuplicate,      // same file, or same ride (start and distance) already in the library
    RAImportStatusUnreadable,
};

/// the outcome of importing several files at once (R2)
@interface RAImportSummary : NSObject
@property (nonatomic) NSUInteger imported;
@property (nonatomic) NSUInteger duplicates;
@property (nonatomic) NSUInteger unreadable;
@end

@interface RALibraryDocument : NSDocument

@property (readonly, nonatomic) NSArray<RARide *> *rides;

/// imports one file (FIT, GPX or TCX, recognized from its content) and keeps a copy of it in the library; undoable
- (RAImportStatus)importData:(NSData *)data fileName:(NSString *)fileName error:(NSError * _Nullable *)error;
/// several files or folders (their files, not recursively), as one undoable action
- (RAImportSummary *)importFilesAtURLs:(NSArray<NSURL *> *)urls;

/// the original file of a ride, nil if missing
- (nullable NSData *)originalDataOfRide:(RARide *)ride;

/// undoable
- (void)renameRide:(RARide *)ride to:(NSString *)name;
/// undoable; the original file goes with it (and comes back on undo)
- (void)removeRides:(NSArray<RARide *> *)rides;

@end

NS_ASSUME_NONNULL_END
