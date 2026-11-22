//
//  RALibraryDocument.m
//  RideAnalyzer
//

#import "RALibraryDocument.h"
#import "RALibraryWindowController.h"
#import "RARide.h"
#import "RAGarminConnect.h"
#import "RAFilter.h"
#import "RARideStats.h"
#import "RARideAnalysis.h"
#import "RAEquipment.h"
#import "RAClimbs.h"
#import "BPTrackReader.h"
#import <CommonCrypto/CommonDigest.h>

NSString *const RALibraryDocumentType = @"fr.free.daniel.braun.ridelib";
NSNotificationName const RALibraryDidChangeNotification = @"RALibraryDidChangeNotification";

static NSString *const RALibraryPlistName = @"Library.plist";
static NSString *const RARidesFolderName = @"Rides";
static const NSInteger RALibraryFormatVersion = 1;
static const NSUInteger RAGarminPageSize = 50;
static const NSUInteger RAGarminMaxPages = 200; // 10,000 activities
static NSString *const RALibraryLocationsKey = @"RALibraryLocations";

static id<RAKeyStore> RAKeyStoreOverride;
static NSUserDefaults *RALocationDefaultsOverride;

// The key kept in a library file is obfuscated, not encrypted: XOR with a pad derived from the library identifier,
// so that it does not show in clear in the file. Anyone with the file and this source can read it.
static NSData *RAKeyPad(NSString *libraryID, NSUInteger length)
{
    NSMutableData *pad = [NSMutableData dataWithCapacity:length + CC_SHA256_DIGEST_LENGTH];
    for (unsigned block = 0; pad.length < length; block++) {
        NSString *seed = [NSString stringWithFormat:@"RideAnalyzer.garminKey.%@.%u", libraryID, block];
        NSData *seedData = [seed dataUsingEncoding:NSUTF8StringEncoding];
        unsigned char digest[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(seedData.bytes, (CC_LONG)seedData.length, digest);
        [pad appendBytes:digest length:sizeof digest];
    }
    pad.length = length;
    return pad;
}

static NSData *RAKeyXor(NSData *data, NSString *libraryID)
{
    NSMutableData *out = [data mutableCopy];
    const unsigned char *p = RAKeyPad(libraryID, data.length).bytes;
    unsigned char *o = out.mutableBytes;
    for (NSUInteger i = 0; i < out.length; i++) o[i] ^= p[i];
    return out;
}

static NSString *RAObfuscatedKey(NSString *key, NSString *libraryID)
{
    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    return [@"1:" stringByAppendingString:[RAKeyXor(data, libraryID) base64EncodedStringWithOptions:0]];
}

static NSString * _Nullable RAKeyFromObfuscated(id value, NSString *libraryID)
{
    if (![value isKindOfClass:[NSString class]] || ![value hasPrefix:@"1:"]) return nil;
    NSData *data = [[NSData alloc] initWithBase64EncodedString:[value substringFromIndex:2] options:0];
    if (data.length == 0) return nil;
    NSString *key = [[NSString alloc] initWithData:RAKeyXor(data, libraryID) encoding:NSUTF8StringEncoding];
    return key.length ? key : nil;
}

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
        if (!ride || !fit) {
            self->_summary.unreadable++;
            self->_progress.completedUnitCount = (int64_t)index + 1;
            [self fetch:index + 1];
            return;
        }
        ride.garminActivityID = a.activityID;
        if (a.name.length) ride.name = a.name;
        void (^next)(void) = ^{
            [self->_candidates addObject:@[ ride, fit ]];
            self->_progress.completedUnitCount = (int64_t)index + 1;
            [self fetch:index + 1];
        };
        // an activity cut in Garmin Connect (e.g. the computer left running in the car): the original file has the
        // whole recording; the GPX export follows the cut, else the summary gives its distance and duration
        if (![RALibraryDocument ride:ride isLongerThanActivity:a data:fit]) {
            next();
            return;
        }
        [self.client gpxExportOfActivity:a.activityID completion:^(NSData *gpx, NSError *gpxError) {
            NSTimeInterval s = 0, e = 0;
            BOOL trim = (gpx && [RALibraryDocument trimOfData:fit matchingGPX:gpx start:&s end:&e])
                     || [RALibraryDocument garminTrimForRide:ride activity:a data:fit start:&s end:&e];
            if (trim) {
                ride.trimStart = s;
                ride.trimEnd = e;
                [RALibraryDocument updateFiguresOfRide:ride fromData:fit];
            }
            next();
        }];
    }];
}

@end

// the corrections of Garmin Connect (applyGarminCorrections:): lists the activities page by page and collects the
// rides to trim. Keeps itself alive while it runs.
@interface RAGarminCorrections : NSObject
@property (weak, nonatomic) RALibraryDocument *document;
@property (strong, nonatomic) RAGarminConnect *client;
@property (copy, nonatomic, nullable) NSDate *since;
@property (strong, nonatomic) NSDictionary<NSString *, RARide *> *byActivity;
@property (strong, nonatomic) NSProgress *progress;
@property (copy, nonatomic, nullable) void (^completion)(NSArray<NSArray *> *toTrim, NSError * _Nullable error);
- (void)listPage:(NSUInteger)page;
@end

@implementation RAGarminCorrections
{
    NSMutableArray<NSArray *> *_toTrim;     // @[ ride, @start, @end ]
    NSMutableArray<NSArray *> *_longer;     // @[ ride, activity, data ]: longer than their activity
}

- (void)finishWithError:(nullable NSError *)error
{
    void (^completion)(NSArray<NSArray *> *, NSError *) = self.completion;
    self.completion = nil;
    if (completion) completion(_toTrim ?: @[], error);
}

- (void)listPage:(NSUInteger)page
{
    if (!_toTrim) _toTrim = [NSMutableArray array];
    if (!_longer) _longer = [NSMutableArray array];
    if (self.progress.cancelled || !self.document) {
        [self finishWithError:nil];
        return;
    }
    [self.client activitiesFrom:page * RAGarminPageSize limit:RAGarminPageSize startDate:self.since
                     completion:^(NSArray<RAGarminActivity *> *activities, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            RALibraryDocument *doc = self.document;
            if (!activities || !doc) {
                [self finishWithError:error];
                return;
            }
            for (RAGarminActivity *a in activities) {
                RARide *ride = self.byActivity[a.activityID];
                NSData *data = ride ? [doc originalDataOfRide:ride] : nil;
                if (data && !ride.trimmed && [RALibraryDocument ride:ride isLongerThanActivity:a data:data]) {
                    [self->_longer addObject:@[ ride, a, data ]];
                }
            }
            if (activities.count == RAGarminPageSize && page + 1 < RAGarminMaxPages) [self listPage:page + 1];
            else [self refine:0];
        });
    }];
}

/// the trim of each longer ride: from the GPX export of its activity (it follows the cut), else from the summary
- (void)refine:(NSUInteger)index
{
    if (index >= _longer.count || self.progress.cancelled) {
        [self finishWithError:nil];
        return;
    }
    RARide *ride = _longer[index][0];
    RAGarminActivity *a = _longer[index][1];
    NSData *data = _longer[index][2];
    [self.client gpxExportOfActivity:a.activityID completion:^(NSData *gpx, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSTimeInterval s = 0, e = 0;
            if ((gpx && [RALibraryDocument trimOfData:data matchingGPX:gpx start:&s end:&e])
                || [RALibraryDocument garminTrimForRide:ride activity:a data:data start:&s end:&e]) {
                [self->_toTrim addObject:@[ ride, @(s), @(e) ]];
            }
            [self refine:index + 1];
        });
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
    NSString *_documentGarminKey;   // in clear in memory, nil when the key is not kept in the document
    BOOL _locationChecked;
    NSAlert *_copyAlert;
    NSMutableArray *_statsCompletions;  // callers waiting for the running computation of missing stats
    RAEquipment *_equipment;
    NSMutableArray<NSDictionary *> *_climbNames;   // @{ @"name", @"climb": climb property list }
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
        _equipment = [[RAEquipment alloc] init];
        _climbNames = [NSMutableArray array];
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

#pragma mark - Garmin Connect key

+ (id<RAKeyStore>)keyStore
{
    return RAKeyStoreOverride ?: [RAKeychainKeyStore shared];
}

+ (void)setKeyStore:(nullable id<RAKeyStore>)keyStore
{
    RAKeyStoreOverride = keyStore;
}

- (nullable NSString *)garminKey
{
    if (_documentGarminKey) return _documentGarminKey;
    return [RALibraryDocument.keyStore keyForLibrary:_libraryID];
}

- (BOOL)keepsGarminKeyInDocument
{
    return _documentGarminKey != nil;
}

- (void)setGarminKey:(nullable NSString *)key keepInDocument:(BOOL)keepInDocument
{
    if (key.length == 0) key = nil;
    id<RAKeyStore> store = RALibraryDocument.keyStore;
    NSString *stored = [store keyForLibrary:_libraryID];
    if (key && keepInDocument) {
        if (stored) [store setKey:nil forLibrary:_libraryID];
        if (![_documentGarminKey isEqualToString:key]) {
            _documentGarminKey = [key copy];
            [self updateChangeCount:NSChangeDone];
        }
    } else {
        if (!(key == stored || [key isEqualToString:stored])) [store setKey:key forLibrary:_libraryID];
        if (_documentGarminKey) {
            _documentGarminKey = nil;
            [self updateChangeCount:NSChangeDone];
        }
    }
}

#pragma mark - copies

+ (NSUserDefaults *)locationDefaults
{
    return RALocationDefaultsOverride ?: [NSUserDefaults standardUserDefaults];
}

+ (void)setLocationDefaults:(nullable NSUserDefaults *)defaults
{
    RALocationDefaultsOverride = defaults;
}

- (nullable NSString *)recordedPath
{
    id locations = [RALibraryDocument.locationDefaults dictionaryForKey:RALibraryLocationsKey][_libraryID];
    return [locations isKindOfClass:[NSString class]] ? locations : nil;
}

- (void)recordLocation
{
    NSString *path = self.fileURL.URLByStandardizingPath.path;
    if (!path || [path isEqualToString:self.recordedPath]) return;
    NSUserDefaults *defaults = RALibraryDocument.locationDefaults;
    NSMutableDictionary *locations = [[defaults dictionaryForKey:RALibraryLocationsKey] mutableCopy]
        ?: [NSMutableDictionary dictionary];
    locations[_libraryID] = path;
    [defaults setObject:locations forKey:RALibraryLocationsKey];
}

- (RALibraryLocation)location
{
    for (NSDocument *doc in [NSDocumentController sharedDocumentController].documents) {
        if (doc != self && [doc isKindOfClass:[RALibraryDocument class]]
            && [((RALibraryDocument *)doc).libraryID isEqualToString:_libraryID]) {
            return RALibraryLocationOpenElsewhere;
        }
    }
    NSString *path = self.fileURL.URLByStandardizingPath.path;
    NSString *recorded = self.recordedPath;
    if (!path || !recorded) return RALibraryLocationNew;
    return [recorded isEqualToString:path] ? RALibraryLocationSame : RALibraryLocationMoved;
}

- (void)becomeCopyCarryingKey:(BOOL)carryKey
{
    NSString *oldID = _libraryID;
    _libraryID = [NSUUID UUID].UUIDString;
    id<RAKeyStore> store = RALibraryDocument.keyStore;
    if (carryKey) {
        NSString *key = [store keyForLibrary:oldID];
        if (key) [store setKey:key forLibrary:_libraryID];
    } else {
        _documentGarminKey = nil;
        _garminLastFetch = nil;
    }
    [self updateChangeCount:NSChangeDone];
    [self recordLocation];
    [self libraryDidChange];
}

- (void)showWindows
{
    [super showWindows];
    [self checkLocation];
}

// asks once, when the window of a library opened from a file shows
- (void)checkLocation
{
    if (_locationChecked || !self.fileURL) return;
    _locationChecked = YES;
    RALibraryLocation location = self.location;
    if (location == RALibraryLocationNew || location == RALibraryLocationSame) {
        [self recordLocation];
        return;
    }
    NSWindow *window = self.windowForSheet;
    if (!window) return;
    NSAlert *alert = [[NSAlert alloc] init];
    BOOL moved = location == RALibraryLocationMoved;
    if (moved) {
        alert.messageText = NSLocalizedString(@"Was this library moved or copied?", @"copy of a library");
        alert.informativeText = [NSString stringWithFormat:NSLocalizedString(
            @"It was last opened from “%@”. A copy for someone else gets its own Garmin Connect key and fetches its "
            @"rides from the start.", @"copy of a library"), self.recordedPath.stringByAbbreviatingWithTildeInPath];
        [alert addButtonWithTitle:NSLocalizedString(@"Moved", @"copy of a library")];
    } else {
        alert.messageText = NSLocalizedString(@"This library is a copy of an open library", @"copy of a library");
        alert.informativeText = NSLocalizedString(
            @"A copy for someone else gets its own Garmin Connect key and fetches its rides from the start.",
            @"copy of a library");
    }
    [alert addButtonWithTitle:NSLocalizedString(@"Copy for Someone Else", @"copy of a library")];
    [alert addButtonWithTitle:NSLocalizedString(@"Copy for Me", @"copy of a library")];
    _copyAlert = alert;
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
        self->_copyAlert = nil;
        NSInteger button = response - NSAlertFirstButtonReturn;
        if (moved) button -= 1;     // -1: moved, 0: someone else, 1: me
        if (button < 0) {
            [self recordLocation];
        } else {
            [self becomeCopyCarryingKey:button == 1];
        }
    }];
}

- (void)saveToURL:(NSURL *)url ofType:(NSString *)typeName forSaveOperation:(NSSaveOperationType)saveOperation
completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
    // Save As keeps the old file: this document becomes a copy, for the same person
    if (saveOperation == NSSaveAsOperation && self.fileURL && ![url.URLByStandardizingPath isEqual:self.fileURL.URLByStandardizingPath]) {
        [self becomeCopyCarryingKey:YES];
    }
    [super saveToURL:url ofType:typeName forSaveOperation:saveOperation completionHandler:^(NSError *error) {
        if (!error && saveOperation != NSAutosaveElsewhereOperation) [self recordLocation];
        completionHandler(error);
    }];
}

- (void)moveToURL:(NSURL *)url completionHandler:(nullable void (^)(NSError * _Nullable))completionHandler
{
    [super moveToURL:url completionHandler:^(NSError *error) {
        if (!error) [self recordLocation];
        if (completionHandler) completionHandler(error);
    }];
}

- (nullable __kindof NSDocument *)duplicateAndReturnError:(NSError * _Nullable *)outError
{
    NSDocument *copy = [super duplicateAndReturnError:outError];
    if ([copy isKindOfClass:[RALibraryDocument class]]) [(RALibraryDocument *)copy becomeCopyCarryingKey:YES];
    return copy;
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
    if (_documentGarminKey) plist[@"garminKey"] = RAObfuscatedKey(_documentGarminKey, _libraryID);
    plist[@"equipment"] = _equipment.propertyList;
    plist[@"climbNames"] = _climbNames;
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
    _documentGarminKey = RAKeyFromObfuscated(plist[@"garminKey"], _libraryID);
    _equipment = [RAEquipment equipmentWithPropertyList:plist[@"equipment"]];
    _climbNames = [NSMutableArray array];
    id names = plist[@"climbNames"];
    if ([names isKindOfClass:[NSArray class]]) {
        for (id n in names) {
            if ([n isKindOfClass:[NSDictionary class]] && [n[@"name"] isKindOfClass:[NSString class]]
                && [RAClimb climbWithPropertyList:n[@"climb"]]) [_climbNames addObject:n];
        }
    }
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
    if (ride.deviceName.length == 0 && reader.deviceProduct != nil
        && (reader.deviceManufacturer == nil || reader.deviceManufacturer.integerValue == 1)) { // Garmin
        ride.deviceName = [RARide nameOfGarminProduct:reader.deviceProduct.integerValue] ?: @"";
    }
    ride.sport = reader.sport ?: @"";
    // the gain computed by the device (FIT): better filtered than one from the points (forum thread of #91)
    if (reader.deviceAscent != nil && reader.deviceAscent.doubleValue > 0) ride.ascent = reader.deviceAscent.doubleValue;
    ride.stats = [RARideStats statsOfAnalysis:[[RARideAnalysis alloc] initWithTrace:reader.trace metrics:reader.metrics
                                                                         calories:reader.calories hasTimes:reader.hasTimes]];
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
        if (ride.bikeID.length == 0) ride.bikeID = _equipment.defaultBikeID;   // R13
        [_rides addObject:ride];
    }
    __weak RALibraryDocument *weakSelf = self;
    [self.undoManager registerUndoWithTarget:self handler:^(id target) {
        [weakSelf removeRides:rides];
    }];
    [self libraryDidChange];
}

+ (void)updateFiguresOfRide:(RARide *)ride fromData:(NSData *)data
{
    RARideAnalysis *a = [RARideAnalysis analysisOfData:data trimStart:ride.trimStart trimEnd:ride.trimEnd];
    if (!a) return;
    ride.distance = a.distance;
    ride.ascent = a.ascent;
    if (!ride.trimmed) {
        // the whole recording: the gain computed by the device, when the file has it; a trimmed ride keeps the gain
        // computed from its points (the device's covers the whole recording)
        BPTrackReader *reader = [BPTrackReader readerWithData:data error:NULL];
        if (reader.deviceAscent != nil && reader.deviceAscent.doubleValue > 0) ride.ascent = reader.deviceAscent.doubleValue;
    }
    if (a.hasTimes) {
        ride.duration = a.elapsedTime;
        ride.startDate = a.trace.firstObject.timestamp;
    }
    ride.stats = [RARideStats statsOfAnalysis:a];
}

- (void)trimRide:(RARide *)ride start:(NSTimeInterval)start end:(NSTimeInterval)end
{
    start = MAX(0, start);
    end = end > start ? end : 0;
    if (start == ride.trimStart && end == ride.trimEnd) return;
    NSData *data = [self originalDataOfRide:ride];
    if (!data) return;
    NSTimeInterval oldStart = ride.trimStart, oldEnd = ride.trimEnd;
    ride.trimStart = start;
    ride.trimEnd = end;
    [RALibraryDocument updateFiguresOfRide:ride fromData:data];
    __weak RALibraryDocument *weakSelf = self;
    [self.undoManager registerUndoWithTarget:self handler:^(id target) {
        [weakSelf trimRide:ride start:oldStart end:oldEnd];
    }];
    if (!self.undoManager.undoing && !self.undoManager.redoing) {
        [self.undoManager setActionName:NSLocalizedString(@"Trim Ride", @"undo action name")];
    }
    [self libraryDidChange];
}

+ (BOOL)ride:(RARide *)ride isLongerThanActivity:(RAGarminActivity *)activity data:(NSData *)data
{
    if (activity.distance <= 0) return NO;
    RARideAnalysis *whole = [RARideAnalysis analysisOfData:data];
    return whole && whole.hasTimes && whole.distance > activity.distance * 1.03 + 300;
}

+ (BOOL)trimOfData:(NSData *)data matchingGPX:(NSData *)gpx start:(NSTimeInterval *)start end:(NSTimeInterval *)end
{
    BPTrackReader *file = [BPTrackReader readerWithData:data error:NULL];
    BPTrackReader *cut = [BPTrackReader readerWithData:gpx error:NULL];
    if (!file.hasTimes || !cut.hasTimes || file.trace.count < 2 || cut.trace.count < 2) return NO;
    NSDate *t0 = file.trace.firstObject.timestamp, *t1 = file.trace.lastObject.timestamp;
    NSDate *c0 = cut.trace.firstObject.timestamp, *c1 = cut.trace.lastObject.timestamp;
    NSTimeInterval s = MAX(0, [c0 timeIntervalSinceDate:t0]);
    NSTimeInterval e = [c1 timeIntervalSinceDate:t0];
    if (s < 20) s = 0;                                       // the export starts a few seconds after the file
    BOOL endCut = [t1 timeIntervalSinceDate:c1] > 20;
    if (s == 0 && !endCut) return NO;                        // the whole file
    if (start) *start = s;
    if (end) *end = endCut ? e + 1 : 0;
    return YES;
}

+ (BOOL)garminTrimForRide:(RARide *)ride activity:(RAGarminActivity *)activity data:(NSData *)data
                    start:(NSTimeInterval *)start end:(NSTimeInterval *)end
{
    if (activity.distance <= 0) return NO;
    RARideAnalysis *whole = [RARideAnalysis analysisOfData:data];
    if (!whole || !whole.hasTimes) return NO;
    if (whole.distance <= activity.distance * 1.03 + 300) return NO;     // the same: nothing was cut
    NSDate *t0 = whole.trace.firstObject.timestamp;
    NSTimeInterval s = 0;
    if (activity.startDate && t0) s = MAX(0, [activity.startDate timeIntervalSinceDate:(NSDate *)t0]);
    if (s < 30) s = 0;                                                   // clock differences
    NSTimeInterval e = 0;
    if (activity.elapsedDuration > 0) {
        e = s + activity.elapsedDuration;
    } else {
        // the time at which the ride covered the activity's distance (from the trimmed start)
        NSUInteger first = [RARideAnalysis rangeOfTrace:whole.trace trimStart:s trimEnd:0].location;
        double d0 = first < whole.count ? whole.distances[first].doubleValue : 0;
        for (NSUInteger i = first; i < whole.count; i++) {
            if (whole.distances[i].doubleValue - d0 >= activity.distance) { e = whole.elapsed[i].doubleValue; break; }
        }
    }
    if (e <= s || e >= whole.elapsedTime) return NO;
    if (start) *start = s;
    if (end) *end = e;
    return YES;
}

- (nullable NSProgress *)applyGarminCorrections:(RAGarminConnect *)client
                                     completion:(void (^)(NSUInteger corrected, NSError * _Nullable error))completion
{
    if (_importing) return nil;
    NSMutableDictionary<NSString *, RARide *> *byActivity = [NSMutableDictionary dictionary];
    NSDate *oldest = nil;
    for (RARide *r in _rides) {
        if (!r.garminActivityID.length) continue;
        byActivity[r.garminActivityID] = r;
        if (r.startDate && (!oldest || [r.startDate compare:oldest] == NSOrderedAscending)) oldest = r.startDate;
    }
    NSProgress *progress = [NSProgress discreteProgressWithTotalUnitCount:1];
    progress.cancellable = YES;
    progress.localizedDescription = NSLocalizedString(@"Comparing the rides with Garmin Connect…", @"progress");
    if (byActivity.count == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(0, nil); });
        return progress;
    }
    _importing = YES;
    RAGarminCorrections *c = [[RAGarminCorrections alloc] init];
    c.document = self;
    c.client = client;
    c.since = oldest ? [[NSCalendar currentCalendar] startOfDayForDate:(NSDate *)oldest] : nil;
    c.byActivity = byActivity;
    c.progress = progress;
    __weak RALibraryDocument *weakSelf = self;
    c.completion = ^(NSArray<NSArray *> *toTrim, NSError *error) {
        RALibraryDocument *me = weakSelf;
        if (!me) return;
        me->_importing = NO;
        if (toTrim.count && !progress.cancelled) {
            [me.undoManager beginUndoGrouping];
            for (NSArray *t in toTrim) [me trimRide:t[0] start:[t[1] doubleValue] end:[t[2] doubleValue]];
            [me.undoManager endUndoGrouping];
            [me.undoManager setActionName:NSLocalizedString(@"Apply Garmin Connect Corrections", @"undo action name")];
        }
        completion(progress.cancelled ? 0 : toTrim.count, error);
    };
    [c listPage:0];
    return progress;
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
    // rides imported before the names of the products (and FIT files: they have only numbers)
    NSInteger product = [RARide productOfDeviceKey:deviceKey];
    label = product > 0 ? [RARide nameOfGarminProduct:product] : nil;
    if (label) return label;
    return product > 0 ? [NSString stringWithFormat:NSLocalizedString(@"Device %ld", @"device: product number"), (long)product]
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

#pragma mark - stats of older rides (R6)

- (NSArray<RARide *> *)ridesWithoutStats
{
    NSMutableArray<RARide *> *rides = [NSMutableArray array];
    for (RARide *r in _rides) if (!r.stats) [rides addObject:r];
    return rides;
}

- (void)computeMissingStatsWithCompletion:(void (^)(NSUInteger computed))completion
{
    // one computation at a time (the Trends and Map tabs both ask): later callers wait for the running one
    if (_statsCompletions) {
        [_statsCompletions addObject:[completion copy]];
        return;
    }
    NSArray<RARide *> *rides = [self ridesWithoutStats];
    if (rides.count == 0) {
        completion(0);
        return;
    }
    _statsCompletions = [NSMutableArray arrayWithObject:[completion copy]];
    NSMutableArray<NSData *> *datas = [NSMutableArray array];
    NSMutableArray<NSArray<NSNumber *> *> *trims = [NSMutableArray array];
    for (RARide *r in rides) {
        [datas addObject:[self originalDataOfRide:r] ?: [NSData data]];
        [trims addObject:@[ @(r.trimStart), @(r.trimEnd) ]];
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableArray *results = [NSMutableArray array];
        for (NSUInteger k = 0; k < datas.count; k++) {
            @autoreleasepool {
                NSData *data = datas[k];
                RARideAnalysis *a = data.length ? [RARideAnalysis analysisOfData:data trimStart:trims[k][0].doubleValue
                                                                        trimEnd:trims[k][1].doubleValue] : nil;
                [results addObject:a ? (id)[RARideStats statsOfAnalysis:a] : (id)[NSNull null]];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSUInteger computed = 0;
            for (NSUInteger i = 0; i < rides.count; i++) {
                if ([results[i] isKindOfClass:[RARideStats class]] && [self->_rides containsObject:rides[i]]) {
                    rides[i].stats = results[i];
                    computed++;
                }
            }
            if (computed) {
                [self updateChangeCount:NSChangeDone]; // derived figures, saved with the library; not undoable
                [self libraryDidChange];
            }
            NSArray *completions = self->_statsCompletions;
            self->_statsCompletions = nil;
            for (void (^c)(NSUInteger) in completions) c(computed);
        });
    });
}

#pragma mark - equipment (R13)

- (RAEquipment *)equipment
{
    return _equipment;
}

/// the bike of each ride, by identifier
- (NSDictionary<NSString *, NSString *> *)rideBikes
{
    NSMutableDictionary<NSString *, NSString *> *d = [NSMutableDictionary dictionary];
    for (RARide *r in _rides) d[r.identifier] = r.bikeID;
    return d;
}

- (void)restoreEquipment:(NSDictionary *)plist rideBikes:(NSDictionary<NSString *, NSString *> *)bikes
              actionName:(NSString *)actionName
{
    NSDictionary *currentPlist = _equipment.propertyList;
    NSDictionary *currentBikes = [self rideBikes];
    _equipment = [RAEquipment equipmentWithPropertyList:plist];
    for (RARide *r in _rides) {
        NSString *b = bikes[r.identifier];
        if (b) r.bikeID = b;
    }
    __weak RALibraryDocument *weakSelf = self;
    [self.undoManager registerUndoWithTarget:self handler:^(id target) {
        [weakSelf restoreEquipment:currentPlist rideBikes:currentBikes actionName:actionName];
    }];
    [self.undoManager setActionName:actionName];
    [self libraryDidChange];
}

- (void)changeEquipment:(void (^)(RAEquipment *equipment))change actionName:(NSString *)actionName
{
    NSDictionary *oldPlist = _equipment.propertyList;
    NSDictionary *oldBikes = [self rideBikes];
    RAEquipment *e = [_equipment copy];
    change(e);
    if ([e.propertyList isEqual:oldPlist]) return;
    if (e.defaultBikeID.length && [e bikeWithID:e.defaultBikeID]) {
        for (RARide *r in _rides) {
            if (r.bikeID.length == 0 || ![e bikeWithID:r.bikeID]) r.bikeID = e.defaultBikeID; // none, or deleted
        }
    }
    _equipment = e;
    __weak RALibraryDocument *weakSelf = self;
    [self.undoManager registerUndoWithTarget:self handler:^(id target) {
        [weakSelf restoreEquipment:oldPlist rideBikes:oldBikes actionName:actionName];
    }];
    [self.undoManager setActionName:actionName];
    [self libraryDidChange];
}

- (void)setBikeID:(NSString *)bikeID ofRides:(NSArray<RARide *> *)rides
{
    NSMutableDictionary<NSString *, NSString *> *old = [NSMutableDictionary dictionary];
    for (RARide *r in rides) {
        if ([r.bikeID isEqualToString:bikeID]) continue;
        old[r.identifier] = r.bikeID;
        r.bikeID = bikeID;
    }
    if (old.count == 0) return;
    NSDictionary *plist = _equipment.propertyList;
    __weak RALibraryDocument *weakSelf = self;
    NSString *name = NSLocalizedString(@"Set Bike", @"undo action name");
    [self.undoManager registerUndoWithTarget:self handler:^(id target) {
        [weakSelf restoreEquipment:plist rideBikes:old actionName:name];
    }];
    [self.undoManager setActionName:name];
    [self libraryDidChange];
}

- (NSArray<RAPart *> *)takeNewlyWornParts
{
    NSMutableArray<RAPart *> *parts = [NSMutableArray array];
    for (RAPart *p in [_equipment wornPartsWithRides:_rides]) {
        if (p.wearWarned) continue;
        p.wearWarned = YES;
        [parts addObject:p];
    }
    if (parts.count) [self updateChangeCount:NSChangeDone];
    return parts;
}

#pragma mark - names of the climbs (R7)

- (NSUInteger)indexOfClimbName:(RAClimb *)climb
{
    for (NSUInteger i = 0; i < _climbNames.count; i++) {
        RAClimb *named = [RAClimb climbWithPropertyList:_climbNames[i][@"climb"]];
        if (named && [named isSameClimbAs:climb]) return i;
    }
    return NSNotFound;
}

- (NSString *)nameOfClimb:(RAClimb *)climb
{
    NSUInteger i = [self indexOfClimbName:climb];
    return i == NSNotFound ? @"" : _climbNames[i][@"name"];
}

- (void)setName:(NSString *)name ofClimb:(RAClimb *)climb
{
    NSString *clean = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *old = [self nameOfClimb:climb];
    if ([old isEqualToString:clean]) return;
    NSUInteger i = [self indexOfClimbName:climb];
    if (i != NSNotFound) [_climbNames removeObjectAtIndex:i];
    if (clean.length) [_climbNames addObject:@{ @"name": clean, @"climb": climb.propertyList }];
    __weak RALibraryDocument *weakSelf = self;
    [self.undoManager registerUndoWithTarget:self handler:^(id target) {
        [weakSelf setName:old ofClimb:climb];
    }];
    if (!self.undoManager.undoing && !self.undoManager.redoing) {
        [self.undoManager setActionName:NSLocalizedString(@"Name Climb", @"undo action name")];
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
