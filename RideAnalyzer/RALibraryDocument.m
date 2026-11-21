//
//  RALibraryDocument.m
//  RideAnalyzer
//

#import "RALibraryDocument.h"
#import "RALibraryWindowController.h"
#import "RARide.h"
#import "RAGarminConnect.h"
#import "RAFilter.h"
#import "BPTrackReader.h"
#import <CommonCrypto/CommonDigest.h>

NSString *const RALibraryDocumentType = @"fr.free.daniel.braun.ridelib";
NSNotificationName const RALibraryDidChangeNotification = @"RALibraryDidChangeNotification";

static NSString *const RALibraryPlistName = @"Library.plist";
static NSString *const RARidesFolderName = @"Rides";
static const NSInteger RALibraryFormatVersion = 1;
static const NSUInteger RAGarminPageSize = 50;
static const NSUInteger RAGarminMaxPages = 200; // 10,000 activities

@implementation RAImportSummary
@end

// one fetch from Garmin Connect: lists the activities page by page, then downloads the new ones one at a time.
// Keeps itself alive while it runs (the requests' completions hold it).
@interface RAGarminFetch : NSObject
@property (strong, nonatomic) RAGarminConnect *client;
@property (copy, nonatomic, nullable) NSDate *since;
@property (strong, nonatomic) NSSet<NSString *> *known;
@property (copy, nonatomic) void (^completion)(NSArray<NSArray *> *candidates, RAImportSummary *summary, NSError * _Nullable error);
@property (readonly, nonatomic) NSProgress *progress;
- (void)start;
@end

@implementation RAGarminFetch
{
    NSMutableArray<RAGarminActivity *> *_toFetch;
    NSMutableArray<NSArray *> *_candidates;
    RAImportSummary *_summary;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _toFetch = [NSMutableArray array];
        _candidates = [NSMutableArray array];
        _summary = [[RAImportSummary alloc] init];
        _progress = [NSProgress discreteProgressWithTotalUnitCount:1];
        _progress.cancellable = YES;
        _progress.localizedDescription = NSLocalizedString(@"Listing the Garmin Connect activities…", @"progress");
    }
    return self;
}

- (void)start
{
    [self listPage:0];
}

- (void)finishWithError:(nullable NSError *)error
{
    _summary.cancelled = _progress.cancelled;
    void (^completion)(NSArray<NSArray *> *, RAImportSummary *, NSError *) = self.completion;
    self.completion = nil;
    if (completion) completion(_candidates, _summary, error);
}

- (void)listPage:(NSUInteger)page
{
    if (_progress.cancelled) {
        [self finishWithError:nil];
        return;
    }
    [self.client activitiesFrom:page * RAGarminPageSize limit:RAGarminPageSize startDate:self.since
                     completion:^(NSArray<RAGarminActivity *> *activities, NSError *error) {
        if (!activities) {
            [self finishWithError:error];
            return;
        }
        BOOL reachedEnd = NO;
        for (RAGarminActivity *a in activities) {
            if (self.since && a.startDate && [a.startDate compare:(NSDate *)self.since] == NSOrderedAscending) {
                reachedEnd = YES;
                break;
            }
            if ([self.known containsObject:a.activityID]) {
                if (!self.since) { reachedEnd = YES; break; } // newest first: the rest is already there
                self->_summary.duplicates++;
                continue;
            }
            if (a.isOutdoorCycling) [self->_toFetch addObject:a];
        }
        if (!reachedEnd && activities.count == RAGarminPageSize && page + 1 < RAGarminMaxPages) {
            [self listPage:page + 1];
            return;
        }
        self->_progress.totalUnitCount = (int64_t)MAX(self->_toFetch.count, (NSUInteger)1);
        self->_progress.completedUnitCount = 0;
        self->_progress.localizedDescription = [NSString localizedStringWithFormat:
            NSLocalizedString(@"Fetching %lu activities from Garmin Connect…", @"progress"),
            (unsigned long)self->_toFetch.count];
        [self fetch:0];
    }];
}

- (void)fetch:(NSUInteger)index
{
    if (index >= _toFetch.count || _progress.cancelled) {
        [self finishWithError:nil];
        return;
    }
    RAGarminActivity *a = _toFetch[index];
    [self.client fitFileOfActivity:a.activityID completion:^(NSData *fit, NSError *error) {
        NSString *fileName = [NSString stringWithFormat:@"%@.fit", a.activityID];
        RARide *ride = fit ? [RALibraryDocument rideFromData:fit fileName:fileName error:NULL] : nil;
        if (ride && fit) {
            ride.garminActivityID = a.activityID;
            if (a.name.length) ride.name = a.name;
            [self->_candidates addObject:@[ ride, fit ]];
        } else {
            self->_summary.unreadable++;
        }
        self->_progress.completedUnitCount = (int64_t)index + 1;
        [self fetch:index + 1];
    }];
}

@end

@implementation RALibraryDocument
{
    NSMutableArray<RARide *> *_rides;
    NSFileWrapper *_package;        // the whole .ridelib, kept between saves so the original files are not rewritten
    NSFileWrapper *_ridesFolder;    // Rides/ in _package
    NSString *_libraryID;
    NSMutableDictionary<NSString *, NSString *> *_deviceLabels;   // set by the user
    NSMutableDictionary<NSString *, NSString *> *_deviceNames;    // learned from TCX files
    NSDate *_garminLastFetch;
    BOOL _importing;
    NSMutableArray<RASavedFilter *> *_savedFilters;
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
        _libraryID = [NSUUID UUID].UUIDString;
        _deviceLabels = [NSMutableDictionary dictionary];
        _deviceNames = [NSMutableDictionary dictionary];
        _savedFilters = [NSMutableArray array];
    }
    return self;
}

- (NSArray<RARide *> *)rides
{
    return [_rides copy];
}

- (NSString *)libraryID
{
    return _libraryID;
}

- (nullable NSDate *)garminLastFetch
{
    return _garminLastFetch;
}

- (BOOL)isImporting
{
    return _importing;
}

- (void)makeWindowControllers
{
    [self addWindowController:[[RALibraryWindowController alloc] init]];
}

#pragma mark - reading and writing

- (nullable NSFileWrapper *)fileWrapperOfType:(NSString *)typeName error:(NSError * _Nullable *)outError
{
    NSMutableDictionary *plist = [@{
        @"version": @(RALibraryFormatVersion),
        @"libraryID": _libraryID,
        @"rides": [_rides valueForKey:@"propertyList"],
        @"deviceLabels": _deviceLabels,
        @"deviceNames": _deviceNames,
        @"savedFilters": [_savedFilters valueForKey:@"propertyList"],
    } mutableCopy];
    if (_garminLastFetch) plist[@"garminLastFetch"] = _garminLastFetch;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0
                                                             options:0 error:outError];
    if (!data) return nil;
    NSFileWrapper *old = _package.fileWrappers[RALibraryPlistName];
    if (old) [_package removeFileWrapper:old];
    [_package addRegularFileWithContents:data preferredFilename:RALibraryPlistName];
    return _package;
}

static NSMutableDictionary<NSString *, NSString *> *RAStringDictionary(id value)
{
    NSMutableDictionary<NSString *, NSString *> *d = [NSMutableDictionary dictionary];
    if (![value isKindOfClass:[NSDictionary class]]) return d;
    [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
        if ([k isKindOfClass:[NSString class]] && [v isKindOfClass:[NSString class]]) d[k] = v;
    }];
    return d;
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
    id libraryID = plist[@"libraryID"];
    if ([libraryID isKindOfClass:[NSString class]] && [libraryID length]) _libraryID = libraryID;
    _deviceLabels = RAStringDictionary(plist[@"deviceLabels"]);
    _deviceNames = RAStringDictionary(plist[@"deviceNames"]);
    id lastFetch = plist[@"garminLastFetch"];
    _garminLastFetch = [lastFetch isKindOfClass:[NSDate class]] ? lastFetch : nil;
    _savedFilters = [NSMutableArray array];
    id saved = plist[@"savedFilters"];
    if ([saved isKindOfClass:[NSArray class]]) {
        for (id p in saved) {
            RASavedFilter *f = [RASavedFilter savedFilterWithPropertyList:p];
            if (f) [_savedFilters addObject:f];
        }
    }
    [self libraryDidChange];
    return YES;
}

#pragma mark - reading rides (any thread)

+ (NSString *)sha256OfData:(NSData *)data
{
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

+ (nullable RARide *)rideFromData:(NSData *)data fileName:(NSString *)fileName error:(NSError * _Nullable *)error
{
    BPTrackReader *reader = [BPTrackReader readerWithData:data error:error];
    if (!reader) return nil;
    if (reader.trace.count < 2) {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{
                NSLocalizedDescriptionKey: NSLocalizedString(@"The file has no track.", @"import") }];
        }
        return nil;
    }
    RARide *ride = [[RARide alloc] initWithTrace:reader.trace name:fileName.stringByDeletingPathExtension];
    if (!reader.hasTimes) {
        // without times the points carry the read date: no date rather than a wrong one
        ride.startDate = nil;
        ride.duration = 0;
    }
    ride.format = reader.format;
    ride.fileName = fileName;
    ride.contentHash = [self sha256OfData:data];
    ride.deviceKey = [RARide deviceKeyForProduct:reader.deviceProduct serialNumber:reader.deviceSerialNumber];
    ride.deviceName = reader.deviceName ?: @"";
    ride.sport = reader.sport ?: @"";
    return ride;
}

+ (NSArray<NSURL *> *)importableFilesAtURLs:(NSArray<NSURL *> *)urls
{
    NSArray<NSString *> *extensions = @[ @"fit", @"gpx", @"tcx" ];
    NSMutableArray<NSURL *> *files = [NSMutableArray array];
    for (NSURL *url in urls) {
        NSNumber *isDir = nil;
        [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:NULL];
        if (!isDir.boolValue) {
            [files addObject:url];
            continue;
        }
        NSDirectoryEnumerator<NSURL *> *e = [[NSFileManager defaultManager] enumeratorAtURL:url
            includingPropertiesForKeys:@[ NSURLIsDirectoryKey ]
            options:NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsPackageDescendants
            errorHandler:nil];
        NSMutableArray<NSURL *> *found = [NSMutableArray array];
        for (NSURL *f in e) {
            if ([extensions containsObject:f.pathExtension.lowercaseString]) [found addObject:f];
        }
        [found sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
            return [a.path compare:b.path];
        }];
        [files addObjectsFromArray:found];
    }
    return files;
}

+ (NSArray<NSURL *> *)deviceActivityFoldersInVolumes:(nullable NSArray<NSURL *> *)volumes
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!volumes) {
        volumes = [fm mountedVolumeURLsIncludingResourceValuesForKeys:nil
                                                              options:NSVolumeEnumerationSkipHiddenVolumes] ?: @[];
    }
    NSMutableArray<NSURL *> *folders = [NSMutableArray array];
    for (NSURL *volume in volumes) {
        for (NSString *path in @[ @"Garmin/Activity", @"GARMIN/ACTIVITY" ]) {
            NSURL *folder = [volume URLByAppendingPathComponent:path isDirectory:YES];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:folder.path isDirectory:&isDir] && isDir) {
                [folders addObject:folder];
                break;
            }
        }
    }
    return folders;
}

#pragma mark - adding rides (main thread)

- (nullable RARide *)existingRideMatching:(RARide *)candidate
{
    return [self rideMatching:candidate in:_rides];
}

- (nullable RARide *)rideMatching:(RARide *)candidate in:(NSArray<RARide *> *)rides
{
    for (RARide *r in rides) {
        if (candidate.contentHash.length && [r.contentHash isEqualToString:candidate.contentHash]) return r;
        if (candidate.garminActivityID.length && [r.garminActivityID isEqualToString:candidate.garminActivityID]) return r;
        if ([r isProbablySameRideAs:candidate]) return r;
    }
    return nil;
}

// candidates: @[ ride, data ] pairs. The new ones are added in one undoable action; a duplicate of a ride without
// Garmin activity gets the candidate's (so the next fetches stop at it)
- (RAImportSummary *)addCandidates:(NSArray<NSArray *> *)candidates
{
    RAImportSummary *summary = [[RAImportSummary alloc] init];
    NSMutableArray<RARide *> *rides = [NSMutableArray array];
    NSMutableArray<NSData *> *datas = [NSMutableArray array];
    BOOL linked = NO;
    for (NSArray *pair in candidates) {
        RARide *ride = pair[0];
        RARide *existing = [self existingRideMatching:ride] ?: [self rideMatching:ride in:rides];
        if (existing) {
            summary.duplicates++;
            if (ride.garminActivityID.length && existing.garminActivityID.length == 0) {
                existing.garminActivityID = ride.garminActivityID;
                linked = YES;
            }
            continue;
        }
        [rides addObject:ride];
        [datas addObject:pair[1]];
    }
    summary.imported = rides.count;
    if (rides.count) {
        [self insertRides:rides files:datas];
        [self.undoManager setActionName:NSLocalizedString(@"Import", @"undo action name")];
    } else if (linked) {
        [self updateChangeCount:NSChangeDone];
    }
    return summary;
}

- (RAImportStatus)importData:(NSData *)data fileName:(NSString *)fileName error:(NSError * _Nullable *)error
{
    RARide *ride = [RALibraryDocument rideFromData:data fileName:fileName error:error];
    if (!ride) return RAImportStatusUnreadable;
    RAImportSummary *s = [self addCandidates:@[ @[ ride, data ] ]];
    return s.imported ? RAImportStatusImported : RAImportStatusDuplicate;
}

- (nullable NSProgress *)importFilesAtURLs:(NSArray<NSURL *> *)urls
                                completion:(void (^)(RAImportSummary *summary))completion
{
    if (_importing) return nil;
    NSArray<NSURL *> *files = [RALibraryDocument importableFilesAtURLs:urls];
    NSProgress *progress = [NSProgress discreteProgressWithTotalUnitCount:(int64_t)files.count];
    progress.cancellable = YES;
    progress.localizedDescription = NSLocalizedString(@"Importing files…", @"progress");
    _importing = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<NSArray *> *candidates = [NSMutableArray array];
        NSUInteger unreadable = 0;
        for (NSURL *url in files) {
            if (progress.cancelled) break;
            @autoreleasepool {
                NSData *data = [NSData dataWithContentsOfURL:url];
                RARide *ride = data ? [RALibraryDocument rideFromData:data fileName:url.lastPathComponent error:NULL] : nil;
                if (ride) [candidates addObject:@[ ride, data ]];
                else unreadable++;
            }
            progress.completedUnitCount++;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            RAImportSummary *summary = [self addCandidates:candidates];
            summary.unreadable = unreadable;
            summary.cancelled = progress.cancelled;
            self->_importing = NO;
            completion(summary);
        });
    });
    return progress;
}

#pragma mark - Garmin Connect (R1)

- (nullable NSProgress *)fetchFromGarmin:(RAGarminConnect *)client since:(nullable NSDate *)since
                              completion:(void (^)(RAImportSummary * _Nullable summary, NSError * _Nullable error))completion
{
    if (_importing) return nil;
    _importing = YES;
    NSMutableSet<NSString *> *known = [NSMutableSet set];
    for (RARide *r in _rides) if (r.garminActivityID.length) [known addObject:r.garminActivityID];
    RAGarminFetch *fetch = [[RAGarminFetch alloc] init];
    fetch.client = client;
    fetch.since = since;
    fetch.known = known;
    __weak RALibraryDocument *weakSelf = self;
    fetch.completion = ^(NSArray<NSArray *> *candidates, RAImportSummary *summary, NSError *error) {
        RALibraryDocument *me = weakSelf;
        if (!me) return;
        me->_importing = NO;
        if (error) {
            completion(nil, error);
            return;
        }
        RAImportSummary *added = [me addCandidates:candidates];
        summary.imported = added.imported;
        summary.duplicates += added.duplicates;
        if (!summary.cancelled) {
            me->_garminLastFetch = [NSDate date];
            if (added.imported == 0) [me updateChangeCount:NSChangeDone]; // the date is saved
        }
        completion(summary, nil);
    };
    [fetch start];
    return fetch.progress;
}

- (nullable NSData *)originalDataOfRide:(RARide *)ride
{
    return _ridesFolder.fileWrappers[ride.fileName].regularFileContents;
}

#pragma mark - edits (all undoable)

// adds rides with their original files (put in Rides/ if not there yet, under a unique name)
- (void)insertRides:(NSArray<RARide *> *)rides files:(NSArray<NSData *> *)files
{
    for (NSUInteger i = 0; i < rides.count; i++) {
        RARide *ride = rides[i];
        if (!_ridesFolder.fileWrappers[ride.fileName]) {
            NSString *preferred = ride.fileName.length ? ride.fileName
                                                       : [ride.identifier stringByAppendingPathExtension:ride.format];
            ride.fileName = [_ridesFolder addRegularFileWithContents:files[i] preferredFilename:preferred];
        }
        if (ride.deviceKey.length && ride.deviceName.length && !_deviceNames[ride.deviceKey]) {
            _deviceNames[ride.deviceKey] = ride.deviceName;
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

#pragma mark - devices

- (NSString *)labelForDeviceKey:(NSString *)deviceKey
{
    NSString *label = _deviceLabels[deviceKey] ?: _deviceNames[deviceKey];
    if (label.length) return label;
    // p<product>-s<serial>
    NSString *first = [deviceKey componentsSeparatedByString:@"-"].firstObject ?: @"";
    NSString *product = first.length > 1 ? [first substringFromIndex:1] : @"";
    return product.length ? [NSString stringWithFormat:NSLocalizedString(@"Device %@", @"device: product number"), product]
                          : NSLocalizedString(@"Unknown device", @"device");
}

- (NSArray<NSString *> *)deviceKeys
{
    NSArray<NSString *> *keys = [[NSSet setWithArray:[_rides valueForKey:@"deviceKey"]] allObjects];
    return [keys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [[self labelForDeviceKey:a] localizedStandardCompare:[self labelForDeviceKey:b]];
    }];
}

- (void)setLabel:(nullable NSString *)label forDeviceKey:(NSString *)deviceKey
{
    NSString *old = _deviceLabels[deviceKey];
    NSString *newLabel = label.length ? [label copy] : nil;
    if (old == newLabel || [old isEqualToString:newLabel]) return;
    _deviceLabels[deviceKey] = newLabel;
    __weak RALibraryDocument *weakSelf = self;
    [self.undoManager registerUndoWithTarget:self handler:^(id target) {
        [weakSelf setLabel:old forDeviceKey:deviceKey];
    }];
    if (!self.undoManager.undoing && !self.undoManager.redoing) {
        [self.undoManager setActionName:NSLocalizedString(@"Rename Device", @"undo action name")];
    }
    [self libraryDidChange];
}

#pragma mark - notes, tags, saved filters

- (void)setNotes:(NSString *)notes ofRide:(RARide *)ride
{
    NSString *old = ride.notes;
    if ([old isEqualToString:notes]) return;
    ride.notes = notes;
    __weak RALibraryDocument *weakSelf = self;
    [self.undoManager registerUndoWithTarget:self handler:^(id target) {
        [weakSelf setNotes:old ofRide:ride];
    }];
    if (!self.undoManager.undoing && !self.undoManager.redoing) {
        [self.undoManager setActionName:NSLocalizedString(@"Edit Notes", @"undo action name")];
    }
    [self libraryDidChange];
}

- (void)setTags:(NSArray<NSString *> *)tags ofRide:(RARide *)ride
{
    NSMutableArray<NSString *> *clean = [NSMutableArray array];
    for (NSString *t in tags) {
        NSString *s = [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([s hasPrefix:@"#"]) s = [s substringFromIndex:1];
        if (s.length && ![clean containsObject:s]) [clean addObject:s];
    }
    NSArray<NSString *> *old = ride.tags;
    if ([old isEqualToArray:clean]) return;
    ride.tags = clean;
    __weak RALibraryDocument *weakSelf = self;
    [self.undoManager registerUndoWithTarget:self handler:^(id target) {
        [weakSelf setTags:old ofRide:ride];
    }];
    if (!self.undoManager.undoing && !self.undoManager.redoing) {
        [self.undoManager setActionName:NSLocalizedString(@"Edit Tags", @"undo action name")];
    }
    [self libraryDidChange];
}

- (NSArray<NSString *> *)allTags
{
    NSMutableSet<NSString *> *tags = [NSMutableSet set];
    for (RARide *r in _rides) [tags addObjectsFromArray:r.tags];
    return [tags.allObjects sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

- (NSArray<RASavedFilter *> *)savedFilters
{
    return [_savedFilters copy];
}

- (void)insertSavedFilter:(RASavedFilter *)saved atIndex:(NSUInteger)index
{
    [_savedFilters insertObject:saved atIndex:MIN(index, _savedFilters.count)];
    __weak RALibraryDocument *weakSelf = self;
    [self.undoManager registerUndoWithTarget:self handler:^(id target) {
        [weakSelf removeSavedFilter:saved];
    }];
    [self libraryDidChange];
}

- (RASavedFilter *)saveFilter:(RAFilter *)filter name:(NSString *)name
{
    RASavedFilter *saved = [[RASavedFilter alloc] initWithName:name filter:filter];
    [self insertSavedFilter:saved atIndex:_savedFilters.count];
    [self.undoManager setActionName:NSLocalizedString(@"Save Filter", @"undo action name")];
    return saved;
}

- (void)removeSavedFilter:(RASavedFilter *)savedFilter
{
    NSUInteger index = [_savedFilters indexOfObjectIdenticalTo:savedFilter];
    if (index == NSNotFound) return;
    [_savedFilters removeObjectAtIndex:index];
    __weak RALibraryDocument *weakSelf = self;
    [self.undoManager registerUndoWithTarget:self handler:^(id target) {
        [weakSelf insertSavedFilter:savedFilter atIndex:index];
    }];
    if (!self.undoManager.undoing && !self.undoManager.redoing) {
        [self.undoManager setActionName:NSLocalizedString(@"Delete Filter", @"undo action name")];
    }
    [self libraryDidChange];
}

- (void)renameSavedFilter:(RASavedFilter *)savedFilter to:(NSString *)name
{
    NSString *old = savedFilter.name;
    if (name.length == 0 || [old isEqualToString:name]) return;
    savedFilter.name = name;
    __weak RALibraryDocument *weakSelf = self;
    [self.undoManager registerUndoWithTarget:self handler:^(id target) {
        [weakSelf renameSavedFilter:savedFilter to:old];
    }];
    if (!self.undoManager.undoing && !self.undoManager.redoing) {
        [self.undoManager setActionName:NSLocalizedString(@"Rename Filter", @"undo action name")];
    }
    [self libraryDidChange];
}

- (void)libraryDidChange
{
    [[NSNotificationCenter defaultCenter] postNotificationName:RALibraryDidChangeNotification object:self];
}

@end
