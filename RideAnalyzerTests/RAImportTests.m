//
//  RAImportTests.m
//  RideAnalyzerTests
//
//  Imports of Ride Analyzer (#82, R2): files and folders read in the background with a progress that can be
//  cancelled, one undoable action, duplicates, devices (R3), GPX times, the Activity folder of a device.
//

#import <XCTest/XCTest.h>
#import "RALibraryDocument.h"
#import "RARide.h"
#import "RATestSupport.h"

@interface RAImportTests : XCTestCase
@end

@implementation RAImportTests
{
    NSURL *_folder;
}

- (void)setUp
{
    _folder = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[NSUUID UUID].UUIDString
                                                                              isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:_folder withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtURL:_folder error:NULL];
}

- (NSURL *)write:(NSData *)data to:(NSString *)relativePath
{
    NSURL *url = [_folder URLByAppendingPathComponent:relativePath];
    [[NSFileManager defaultManager] createDirectoryAtURL:url.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:NULL];
    [data writeToURL:url atomically:YES];
    return url;
}

- (RAImportSummary *)importURLs:(NSArray<NSURL *> *)urls into:(RALibraryDocument *)doc
{
    __block RAImportSummary *result = nil;
    NSProgress *progress = [doc importFilesAtURLs:urls completion:^(RAImportSummary *summary) { result = summary; }];
    XCTAssertNotNil(progress);
    XCTAssertTrue(RAWaitUntil(10, ^{ return (BOOL)(result != nil); }));
    XCTAssertEqual(progress.completedUnitCount, progress.totalUnitCount);
    return result;
}

- (void)testImportableFiles
{
    [self write:RAGPX(@[ @1, @2 ], 0) to:@"b.gpx"];
    [self write:RATCX(@[ @1, @2 ], 0, nil, nil) to:@"sub/a.TCX"];
    [self write:RAFIT(@[ @1, @2 ], 0, 1, 2) to:@"sub/deeper/c.fit"];
    [self write:[NSData data] to:@"notes.txt"];
    [self write:RAGPX(@[ @1, @2 ], 0) to:@".hidden.gpx"];
    NSURL *single = [self write:RAGPX(@[ @1, @2 ], 0) to:@"elsewhere/x.data"];
    NSArray<NSURL *> *files = [RALibraryDocument importableFilesAtURLs:@[ _folder, single ]];
    NSArray<NSString *> *names = [files valueForKey:@"lastPathComponent"];
    XCTAssertEqualObjects(names, (@[ @"b.gpx", @"a.TCX", @"c.fit", @"x.data" ]),
                          @"tracks of the folder and its subfolders, sorted by path; a file given as such is kept");
}

- (void)testBackgroundImportOfAFolder
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    doc.undoManager.groupsByEvent = NO;
    [self write:RAGPX(@[ @100, @150, @130 ], 0) to:@"1.gpx"];
    [self write:RATCX(@[ @200, @260 ], 86400, @"Edge 830", @3337) to:@"2.tcx"];
    [self write:RAFIT(@[ @300, @310, @320 ], 2 * 86400, 3122, 3337) to:@"3.fit"];
    [self write:RATCX(@[ @200, @260 ], 86400, @"Edge 830", @3337) to:@"copy/2.tcx"]; // same file again
    [self write:[@"junk" dataUsingEncoding:NSUTF8StringEncoding] to:@"4.gpx"];

    [doc.undoManager beginUndoGrouping];
    RAImportSummary *summary = [self importURLs:@[ _folder ] into:doc];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqual(summary.imported, 3u);
    XCTAssertEqual(summary.duplicates, 1u, @"the same file twice in one import");
    XCTAssertEqual(summary.unreadable, 1u);
    XCTAssertFalse(summary.cancelled);
    XCTAssertFalse(doc.importing);
    XCTAssertEqual(doc.rides.count, 3u);
    XCTAssertEqualObjects(doc.undoManager.undoActionName, @"Import");

    RARide *gpx = [doc.rides filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"format == 'gpx'"]].firstObject;
    XCTAssertNotNil(gpx.startDate, @"GPX <time> is read");
    XCTAssertEqualWithAccuracy(gpx.duration, 1200, 0.001);

    RARide *fit = [doc.rides filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"format == 'fit'"]].firstObject;
    RARide *tcx = [doc.rides filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"format == 'tcx'"]].firstObject;
    XCTAssertEqualObjects(fit.deviceKey, @"p3122-s3337");
    XCTAssertEqualObjects(tcx.deviceKey, @"p3122-s3337", @"same unit, whatever the format");
    XCTAssertEqualObjects(fit.sport, @"cycling");
    XCTAssertEqualObjects([doc labelForDeviceKey:fit.deviceKey], @"Edge 830", @"name learned from the TCX file");
    XCTAssertEqualObjects([doc labelForDeviceKey:gpx.deviceKey], @"Unknown device");

    [doc.undoManager undo];
    XCTAssertEqual(doc.rides.count, 0u, @"the whole import is one action");

    // importing again resumes: everything is a duplicate
    [doc.undoManager redo];
    XCTAssertEqual(doc.rides.count, 3u);
    [doc.undoManager beginUndoGrouping];
    RAImportSummary *again = [self importURLs:@[ _folder ] into:doc];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqual(again.imported, 0u);
    XCTAssertEqual(again.duplicates, 4u);
}

- (void)testCancelledImportKeepsWhatWasRead
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    for (int i = 0; i < 40; i++) {
        [self write:RATCX(@[ @100, @(110 + i) ], i * 86400, nil, nil) to:[NSString stringWithFormat:@"%02d.tcx", i]];
    }
    __block RAImportSummary *result = nil;
    NSProgress *progress = [doc importFilesAtURLs:@[ _folder ] completion:^(RAImportSummary *summary) { result = summary; }];
    XCTAssertNil([doc importFilesAtURLs:@[ _folder ] completion:^(RAImportSummary *summary) {}], @"one at a time");
    [progress cancel];
    XCTAssertTrue(RAWaitUntil(10, ^{ return (BOOL)(result != nil); }));
    XCTAssertTrue(result.cancelled);
    XCTAssertEqual(doc.rides.count, result.imported, @"the files read before the cancellation are kept");
    XCTAssertLessThan(result.imported, 40u);
    XCTAssertFalse(doc.importing);
}

- (void)testDeviceLabels
{
    RALibraryDocument *doc = [[RALibraryDocument alloc] init];
    doc.undoManager.groupsByEvent = NO;
    [doc.undoManager beginUndoGrouping];
    [doc importData:RAFIT(@[ @1, @2 ], 0, 3570, 42) fileName:@"a.fit" error:NULL];
    [doc importData:RAFIT(@[ @1, @3 ], 86400, 3121, 7) fileName:@"b.fit" error:NULL];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqualObjects([doc labelForDeviceKey:@"p3570-s42"], @"Device 3570", @"no name in a FIT file");
    [doc.undoManager beginUndoGrouping];
    [doc setLabel:@"Edge" forDeviceKey:@"p3570-s42"];
    [doc.undoManager endUndoGrouping];
    XCTAssertEqualObjects([doc labelForDeviceKey:@"p3570-s42"], @"Edge");
    XCTAssertEqualObjects(doc.deviceKeys, (@[ @"p3121-s7", @"p3570-s42" ]), @"sorted by label: Device 3121, Edge");
    [doc.undoManager undo];
    XCTAssertEqualObjects([doc labelForDeviceKey:@"p3570-s42"], @"Device 3570");

    // saved with the library
    [doc.undoManager beginUndoGrouping];
    [doc setLabel:@"Montre" forDeviceKey:@"p3121-s7"];
    [doc.undoManager endUndoGrouping];
    NSFileWrapper *package = [doc fileWrapperOfType:RALibraryDocumentType error:NULL];
    NSURL *url = [_folder URLByAppendingPathComponent:@"lib.ridelib"];
    XCTAssertTrue([package writeToURL:url options:0 originalContentsURL:nil error:NULL]);
    RALibraryDocument *reopened = [[RALibraryDocument alloc] init];
    XCTAssertTrue([reopened readFromFileWrapper:[[NSFileWrapper alloc] initWithURL:url options:NSFileWrapperReadingImmediate error:NULL]
                                         ofType:RALibraryDocumentType error:NULL]);
    XCTAssertEqualObjects([reopened labelForDeviceKey:@"p3121-s7"], @"Montre");
}

- (void)testDeviceActivityFolders
{
    NSURL *edge = [_folder URLByAppendingPathComponent:@"EDGE" isDirectory:YES];
    NSURL *usb = [_folder URLByAppendingPathComponent:@"USBKEY" isDirectory:YES];
    [self write:RAFIT(@[ @1, @2 ], 0, 1, 2) to:@"EDGE/Garmin/Activity/2026-11-18-08-00-00.fit"];
    [self write:[NSData data] to:@"USBKEY/Documents/x.txt"];
    NSArray<NSURL *> *folders = [RALibraryDocument deviceActivityFoldersInVolumes:@[ edge, usb ]];
    XCTAssertEqual(folders.count, 1u);
    XCTAssertEqualObjects(folders.firstObject.lastPathComponent, @"Activity");
    XCTAssertTrue([folders.firstObject.path hasPrefix:edge.path]);
    XCTAssertNotNil([RALibraryDocument deviceActivityFoldersInVolumes:nil], @"the mounted volumes: no crash");
}

@end
