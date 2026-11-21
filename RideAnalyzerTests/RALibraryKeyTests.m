//
//  RALibraryKeyTests.m
//  RideAnalyzerTests
//
//  The Garmin Connect key of a library (#82, R15): in the key store (Keychain) by default, or kept obfuscated in
//  the library file; copies of a library (new identifier, with or without the key). Never the user's Keychain or
//  user defaults: a RAMemoryKeyStore and a private user defaults suite.
//

#import <XCTest/XCTest.h>
#import "RALibraryDocument.h"
#import "RAGarminConnect.h"
#import "RAGarminFetchSheet.h"

@interface RALibraryKeyTests : XCTestCase
@end

@implementation RALibraryKeyTests
{
    RAMemoryKeyStore *_store;
    NSString *_suiteName;
    NSUserDefaults *_defaults;
}

- (void)setUp
{
    _store = [[RAMemoryKeyStore alloc] init];
    RALibraryDocument.keyStore = _store;
    _suiteName = [@"RALibraryKeyTests." stringByAppendingString:[NSUUID UUID].UUIDString];
    _defaults = [[NSUserDefaults alloc] initWithSuiteName:_suiteName];
    RALibraryDocument.locationDefaults = _defaults;
}

- (void)tearDown
{
    RALibraryDocument.keyStore = nil;
    RALibraryDocument.locationDefaults = nil;
    [_defaults removePersistentDomainForName:_suiteName];
}

- (NSDictionary *)plistOfDocument:(RALibraryDocument *)doc
{
    NSError *error = nil;
    NSFileWrapper *package = [doc fileWrapperOfType:RALibraryDocumentType error:&error];
    XCTAssertNotNil(package, @"%@", error);
    NSData *data = package.fileWrappers[@"Library.plist"].regularFileContents;
    return data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL] : @{};
}

- (RALibraryDocument *)reopen:(RALibraryDocument *)doc
{
    NSError *error = nil;
    NSFileWrapper *package = [doc fileWrapperOfType:RALibraryDocumentType error:&error];
    // through the serialized form, as from a file
    NSData *plist = package.fileWrappers[@"Library.plist"].regularFileContents;
    NSFileWrapper *copy = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{}];
    [copy addRegularFileWithContents:plist preferredFilename:@"Library.plist"];
    RALibraryDocument *reopened = [[RALibraryDocument alloc] init];
    XCTAssertTrue([reopened readFromFileWrapper:copy ofType:RALibraryDocumentType error:&error], @"%@", error);
    return reopened;
}

- (void)testKeyInKeyStoreByDefault
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    XCTAssertNil(doc.garminKey);
    [doc setGarminKey:@"secret-key-1" keepInDocument:NO];
    XCTAssertEqualObjects([_store keyForLibrary:doc.libraryID], @"secret-key-1");
    XCTAssertEqualObjects(doc.garminKey, @"secret-key-1");
    XCTAssertFalse(doc.keepsGarminKeyInDocument);
    XCTAssertFalse(doc.documentEdited, @"the document does not change");
    XCTAssertNil([self plistOfDocument:doc][@"garminKey"]);

    RALibraryDocument *other = [[RALibraryDocument alloc] init];
    XCTAssertNil(other.garminKey, @"one key per library: two people, one Mac account");
    [doc setGarminKey:@"" keepInDocument:NO];
    XCTAssertNil([_store keyForLibrary:doc.libraryID]);
}

- (void)testKeyKeptInDocument
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    [doc setGarminKey:@"secret-key-2" keepInDocument:NO];
    [doc setGarminKey:@"secret-key-2" keepInDocument:YES];
    XCTAssertNil([_store keyForLibrary:doc.libraryID], @"moved out of the key store");
    XCTAssertTrue(doc.keepsGarminKeyInDocument);
    XCTAssertTrue(doc.documentEdited);

    NSError *error = nil;
    NSFileWrapper *package = [doc fileWrapperOfType:RALibraryDocumentType error:&error];
    NSData *data = package.fileWrappers[@"Library.plist"].regularFileContents;
    NSData *clear = [@"secret-key-2" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertEqual([data rangeOfData:clear options:0 range:NSMakeRange(0, data.length)].location, NSNotFound,
                   @"not in clear in the file");
    NSString *stored = [self plistOfDocument:doc][@"garminKey"];
    XCTAssertNotNil(stored);
    XCTAssertFalse([stored containsString:@"secret"]);

    RALibraryDocument *reopened = [self reopen:doc];
    XCTAssertEqualObjects(reopened.garminKey, @"secret-key-2", @"read back from the file, on another Mac");
    XCTAssertTrue(reopened.keepsGarminKeyInDocument);
    XCTAssertNil([_store keyForLibrary:reopened.libraryID]);

    [reopened setGarminKey:@"secret-key-2" keepInDocument:NO];
    XCTAssertFalse(reopened.keepsGarminKeyInDocument);
    XCTAssertEqualObjects([_store keyForLibrary:reopened.libraryID], @"secret-key-2", @"back to the key store");
    XCTAssertNil([self plistOfDocument:reopened][@"garminKey"]);
}

- (void)testLocation
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    XCTAssertEqual(doc.location, RALibraryLocationNew, @"no file");
    doc.fileURL = [NSURL fileURLWithPath:@"/tmp/ra-tests/Me.ridelib"];
    XCTAssertEqual(doc.location, RALibraryLocationNew);
    [doc recordLocation];
    XCTAssertEqualObjects(doc.recordedPath, doc.fileURL.URLByStandardizingPath.path);
    XCTAssertEqual(doc.location, RALibraryLocationSame);

    RALibraryDocument *copy = [self reopen:doc];
    XCTAssertEqualObjects(copy.libraryID, doc.libraryID);
    copy.fileURL = [NSURL fileURLWithPath:@"/tmp/ra-tests/Me copy.ridelib"];
    XCTAssertEqual(copy.location, RALibraryLocationMoved, @"moved or copied in the Finder: the user says which");

    NSDocumentController *controller = [NSDocumentController sharedDocumentController];
    [controller addDocument:doc];
    XCTAssertEqual(copy.location, RALibraryLocationOpenElsewhere);
    [controller removeDocument:doc];
}

- (void)testCopyForSomeoneElse
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    [doc setGarminKey:@"secret-key-3" keepInDocument:NO];
    RALibraryDocument *copy = [self reopen:doc];
    XCTAssertEqualObjects(copy.garminKey, @"secret-key-3", @"same identifier: same key, until it is a copy");
    [copy becomeCopyCarryingKey:NO];
    XCTAssertNotEqualObjects(copy.libraryID, doc.libraryID);
    XCTAssertNil(copy.garminKey, @"someone else's Garmin Connect account");
    XCTAssertNil(copy.garminLastFetch);
    XCTAssertTrue(copy.documentEdited, @"the new identifier is saved");
    XCTAssertEqualObjects(doc.garminKey, @"secret-key-3", @"the original keeps its key");
    XCTAssertEqualObjects([self plistOfDocument:copy][@"libraryID"], copy.libraryID);

    RALibraryDocument *inFile = [[RALibraryDocument alloc] init];
    [inFile setGarminKey:@"secret-key-4" keepInDocument:YES];
    RALibraryDocument *fileCopy = [self reopen:inFile];
    [fileCopy becomeCopyCarryingKey:NO];
    XCTAssertNil(fileCopy.garminKey, @"the key kept in the file does not go to someone else's copy");
}

- (void)testCopyForMe
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    [doc setGarminKey:@"secret-key-5" keepInDocument:NO];
    RALibraryDocument *copy = [self reopen:doc];
    [copy becomeCopyCarryingKey:YES];
    XCTAssertNotEqualObjects(copy.libraryID, doc.libraryID);
    XCTAssertEqualObjects(copy.garminKey, @"secret-key-5");
    XCTAssertEqualObjects([_store keyForLibrary:doc.libraryID], @"secret-key-5", @"both keep working");

    RALibraryDocument *inFile = [[RALibraryDocument alloc] init];
    [inFile setGarminKey:@"secret-key-6" keepInDocument:YES];
    RALibraryDocument *fileCopy = [self reopen:inFile];
    [fileCopy becomeCopyCarryingKey:YES];
    RALibraryDocument *again = [self reopen:fileCopy];
    XCTAssertEqualObjects(again.garminKey, @"secret-key-6", @"re-encoded with the new identifier");
}

- (void)testFetchSheetKeepBox
{
    RAGarminFetchSheet *sheet = [[RAGarminFetchSheet alloc] initWithKey:@"k" keepInDocument:YES lastFetch:nil];
    (void)sheet.window;
    XCTAssertEqual(sheet.keepInDocumentButton.state, NSControlStateValueOn);
    __block BOOL kept = NO;
    __block NSString *key = nil;
    NSWindow *parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 400)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [sheet beginSheetForWindow:parent completion:^(BOOL fetch, NSString *k, BOOL keepInDocument, NSDate *since) {
        key = k;
        kept = keepInDocument;
    }];
    sheet.keepInDocumentButton.state = NSControlStateValueOff;
    [sheet fetch:self];
    XCTAssertEqualObjects(key, @"k");
    XCTAssertFalse(kept);
}

@end
