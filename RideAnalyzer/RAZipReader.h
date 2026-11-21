//
//  RAZipReader.h
//  RideAnalyzer
//
//  Reads the files of a ZIP archive held in memory (#82, R1): Garmin Connect sends an activity as a ZIP holding its
//  FIT file. Only what such archives use: stored (0) and deflated (8) entries, read through the central directory
//  (so entries written with a data descriptor are read too). No ZIP64, no encryption.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RAZipReader : NSObject

/// file name → content, folders skipped; nil (and an error) for data that is not a ZIP archive or a damaged one
+ (nullable NSDictionary<NSString *, NSData *> *)entriesOfZipData:(NSData *)data error:(NSError * _Nullable *)error;
/// "PK\3\4" at the start
+ (BOOL)isZipData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
