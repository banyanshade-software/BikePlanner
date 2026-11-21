//
//  RALibraryDocument.m
//  RideAnalyzer
//

#import "RALibraryDocument.h"
#import "RALibraryWindowController.h"
#import "RARide.h"
#import "BPTrackReader.h"
#import <CommonCrypto/CommonDigest.h>

NSString *const RALibraryDocumentType = @"fr.free.daniel.braun.ridelib";
NSNotificationName const RALibraryDidChangeNotification = @"RALibraryDidChangeNotification";

static NSString *const RALibraryPlistName = @"Library.plist";
static NSString *const RARidesFolderName = @"Rides";
static const NSInteger RALibraryFormatVersion = 1;

@implementation RAImportSummary
@end

@implementation RALibraryDocument
{
    NSMutableArray<RARide *> *_rides;
    NSFileWrapper *_package;        // the whole .ridelib, kept between saves so the original files are not rewritten
    NSFileWrapper *_ridesFolder;    // Rides/ in _package
}

+ (BOOL)autosavesInPlace
{
    return YES;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _rides = [NSMutableArray array];
        _package = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{}];
        _ridesFolder = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{}];
        _ridesFolder.preferredFilename = RARidesFolderName;
        [_package addFileWrapper:_ridesFolder];
    }
    return self;
}

- (NSArray<RARide *> *)rides
{
    return [_rides copy];
}

- (void)makeWindowControllers
{
    [self addWindowController:[[RALibraryWindowController alloc] init]];
}

#pragma mark - reading and writing

- (nullable NSFileWrapper *)fileWrapperOfType:(NSString *)typeName error:(NSError * _Nullable *)outError
{
    NSDictionary *plist = @{
        @"version": @(RALibraryFormatVersion),
        @"rides": [_rides valueForKey:@"propertyList"],
    };
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0
                                                             options:0 error:outError];
    if (!data) return nil;
    NSFileWrapper *old = _package.fileWrappers[RALibraryPlistName];
    if (old) [_package removeFileWrapper:old];
    [_package addRegularFileWithContents:data preferredFilename:RALibraryPlistName];
    return _package;
}

- (BOOL)readFromFileWrapper:(NSFileWrapper *)fileWrapper ofType:(NSString *)typeName error:(NSError * _Nullable *)outError
{
    NSData *data = fileWrapper.directory ? fileWrapper.fileWrappers[RALibraryPlistName].regularFileContents : nil;
    id plist = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:outError] : nil;
    if (![plist isKindOfClass:[NSDictionary class]] || ![plist[@"rides"] isKindOfClass:[NSArray class]]) {
        if (outError && !*outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:nil];
        }
        return NO;
    }
    NSMutableArray<RARide *> *rides = [NSMutableArray array];
    for (id p in plist[@"rides"]) {
        RARide *ride = [p isKindOfClass:[NSDictionary class]] ? [[RARide alloc] initWithPropertyList:p] : nil;
        if (ride) {
            [rides addObject:ride];
        } else {
            NSLog(@"RideAnalyzer: unreadable ride skipped in %@", self.fileURL.lastPathComponent);
        }
    }
    NSFileWrapper *folder = fileWrapper.fileWrappers[RARidesFolderName];
    if (!folder.directory) {
        if (folder) [fileWrapper removeFileWrapper:folder];
        folder = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{}];
        folder.preferredFilename = RARidesFolderName;
        [fileWrapper addFileWrapper:folder];
    }
    _package = fileWrapper;
    _ridesFolder = folder;
    _rides = rides;
    [self libraryDidChange];
    return YES;
}

#pragma mark - import (R2)

+ (NSString *)sha256OfData:(NSData *)data
{
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

- (RAImportStatus)importData:(NSData *)data fileName:(NSString *)fileName error:(NSError * _Nullable *)error
{
    NSString *hash = [RALibraryDocument sha256OfData:data];
    for (RARide *r in _rides) {
        if ([r.contentHash isEqualToString:hash]) return RAImportStatusDuplicate;
    }
    BPTrackReader *reader = [BPTrackReader readerWithData:data error:error];
    if (!reader || reader.trace.count < 2) return RAImportStatusUnreadable;

    RARide *ride = [[RARide alloc] initWithTrace:reader.trace name:fileName.stringByDeletingPathExtension];
    if ([reader.format isEqualToString:@"gpx"]) {
        // GPXParser does not read <time> and stamps the parse date: no date rather than a wrong one
        ride.startDate = nil;
        ride.duration = 0;
    }
    for (RARide *r in _rides) {
        if ([r isProbablySameRideAs:ride]) return RAImportStatusDuplicate;
    }
    ride.format = reader.format;
    ride.contentHash = hash;
    ride.fileName = [_ridesFolder addRegularFileWithContents:data preferredFilename:fileName];
    [self insertRides:@[ ride ] files:@[ data ]];
    return RAImportStatusImported;
}

- (RAImportSummary *)importFilesAtURLs:(NSArray<NSURL *> *)urls
{
    NSMutableArray<NSURL *> *files = [NSMutableArray array];
    for (NSURL *url in urls) {
        NSNumber *isDir = nil;
        [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:NULL];
        if (isDir.boolValue) {
            NSArray<NSURL *> *content = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:url
                includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
            for (NSURL *f in content) {
                NSString *ext = f.pathExtension.lowercaseString;
                if ([@[ @"fit", @"gpx", @"tcx" ] containsObject:ext]) [files addObject:f];
            }
        } else {
            [files addObject:url];
        }
    }
    RAImportSummary *summary = [[RAImportSummary alloc] init];
    [self.undoManager beginUndoGrouping];
    for (NSURL *url in files) {
        NSData *data = [NSData dataWithContentsOfURL:url];
        RAImportStatus status = data ? [self importData:data fileName:url.lastPathComponent error:NULL]
                                     : RAImportStatusUnreadable;
        switch (status) {
            case RAImportStatusImported: summary.imported++; break;
            case RAImportStatusDuplicate: summary.duplicates++; break;
            case RAImportStatusUnreadable: summary.unreadable++; break;
        }
    }
    [self.undoManager endUndoGrouping];
    [self.undoManager setActionName:NSLocalizedString(@"Import", @"undo action name")];
    return summary;
}

- (nullable NSData *)originalDataOfRide:(RARide *)ride
{
    return _ridesFolder.fileWrappers[ride.fileName].regularFileContents;
}

#pragma mark - edits (all undoable)

// adds rides whose files are already in Rides/ (files: their data, to put back after an undo of the removal)
- (void)insertRides:(NSArray<RARide *> *)rides files:(NSArray<NSData *> *)files
{
    for (NSUInteger i = 0; i < rides.count; i++) {
        RARide *ride = rides[i];
        if (!_ridesFolder.fileWrappers[ride.fileName]) {
            ride.fileName = [_ridesFolder addRegularFileWithContents:files[i] preferredFilename:ride.fileName];
        }
        [_rides addObject:ride];
    }
    __weak RALibraryDocument *weakSelf = self;
    [self.undoManager registerUndoWithTarget:self handler:^(id target) {
        [weakSelf removeRides:rides];
    }];
    [self libraryDidChange];
}

- (void)removeRides:(NSArray<RARide *> *)rides
{
    NSMutableArray<RARide *> *removed = [NSMutableArray array];
    NSMutableArray<NSData *> *files = [NSMutableArray array];
    for (RARide *ride in rides) {
        if (![_rides containsObject:ride]) continue;
        NSFileWrapper *file = _ridesFolder.fileWrappers[ride.fileName];
        [files addObject:file.regularFileContents ?: [NSData data]];
        if (file) [_ridesFolder removeFileWrapper:file];
        [_rides removeObject:ride];
        [removed addObject:ride];
    }
    if (removed.count == 0) return;
    __weak RALibraryDocument *weakSelf = self;
    [self.undoManager registerUndoWithTarget:self handler:^(id target) {
        [weakSelf insertRides:removed files:files];
    }];
    if (!self.undoManager.undoing && !self.undoManager.redoing) {
        [self.undoManager setActionName:NSLocalizedString(@"Delete", @"undo action name")];
    }
    [self libraryDidChange];
}

- (void)renameRide:(RARide *)ride to:(NSString *)name
{
    NSString *old = ride.name;
    if ([old isEqualToString:name]) return;
    ride.name = name;
    __weak RALibraryDocument *weakSelf = self;
    [self.undoManager registerUndoWithTarget:self handler:^(id target) {
        [weakSelf renameRide:ride to:old];
    }];
    if (!self.undoManager.undoing && !self.undoManager.redoing) {
        [self.undoManager setActionName:NSLocalizedString(@"Rename", @"undo action name")];
    }
    [self libraryDidChange];
}

- (void)libraryDidChange
{
    [[NSNotificationCenter defaultCenter] postNotificationName:RALibraryDidChangeNotification object:self];
}

@end
