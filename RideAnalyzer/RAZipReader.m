//
//  RAZipReader.m
//  RideAnalyzer
//

#import "RAZipReader.h"
#import <compression.h>

static NSString *const RAZipErrorDomain = @"RAZipReader";

static uint32_t RAZipRead(const uint8_t *p, NSUInteger size)
{
    uint32_t v = 0;
    for (NSUInteger i = 0; i < size; i++) v |= (uint32_t)p[i] << (8 * i);
    return v;
}

@implementation RAZipReader

+ (BOOL)isZipData:(NSData *)data
{
    return data.length >= 4 && RAZipRead(data.bytes, 4) == 0x04034b50;
}

+ (nullable NSDictionary<NSString *, NSData *> *)fail:(NSString *)reason error:(NSError * _Nullable *)error
{
    if (error) {
        NSString *d = [NSString stringWithFormat:NSLocalizedString(@"The archive could not be read (%@).", @"ZIP"), reason];
        *error = [NSError errorWithDomain:RAZipErrorDomain code:1 userInfo:@{ NSLocalizedDescriptionKey: d }];
    }
    return nil;
}

+ (nullable NSDictionary<NSString *, NSData *> *)entriesOfZipData:(NSData *)data error:(NSError * _Nullable *)error
{
    const uint8_t *b = data.bytes;
    NSUInteger n = data.length;
    if (![self isZipData:data] || n < 22) return [self fail:@"not a ZIP archive" error:error];

    // end of central directory: the last signature, within the last 64 KB + 22 bytes (comment)
    NSInteger eocd = -1;
    NSUInteger lowest = n > 22 + 65535 ? n - 22 - 65535 : 0;
    for (NSUInteger i = n - 22 + 1; i-- > lowest;) {
        if (RAZipRead(b + i, 4) == 0x06054b50) { eocd = (NSInteger)i; break; }
    }
    if (eocd < 0) return [self fail:@"no central directory" error:error];
    NSUInteger count = RAZipRead(b + eocd + 10, 2);
    NSUInteger cdOffset = RAZipRead(b + eocd + 16, 4);

    NSMutableDictionary<NSString *, NSData *> *entries = [NSMutableDictionary dictionary];
    NSUInteger p = cdOffset;
    for (NSUInteger k = 0; k < count; k++) {
        if (p + 46 > n || RAZipRead(b + p, 4) != 0x02014b50) return [self fail:@"central directory" error:error];
        NSUInteger method = RAZipRead(b + p + 10, 2);
        NSUInteger flags = RAZipRead(b + p + 8, 2);
        NSUInteger compressedSize = RAZipRead(b + p + 20, 4);
        NSUInteger size = RAZipRead(b + p + 24, 4);
        NSUInteger nameLength = RAZipRead(b + p + 28, 2);
        NSUInteger extraLength = RAZipRead(b + p + 30, 2);
        NSUInteger commentLength = RAZipRead(b + p + 32, 2);
        NSUInteger localOffset = RAZipRead(b + p + 42, 4);
        if (p + 46 + nameLength > n) return [self fail:@"central directory" error:error];
        NSString *name = [[NSString alloc] initWithBytes:b + p + 46 length:nameLength encoding:NSUTF8StringEncoding]
            ?: [[NSString alloc] initWithBytes:b + p + 46 length:nameLength encoding:NSISOLatin1StringEncoding];
        p += 46 + nameLength + extraLength + commentLength;
        if (flags & 1) return [self fail:@"encrypted" error:error];
        if ([name hasSuffix:@"/"]) continue; // a folder

        if (localOffset + 30 > n || RAZipRead(b + localOffset, 4) != 0x04034b50) {
            return [self fail:@"local header" error:error];
        }
        NSUInteger start = localOffset + 30 + RAZipRead(b + localOffset + 26, 2) + RAZipRead(b + localOffset + 28, 2);
        if (start + compressedSize > n) return [self fail:@"truncated" error:error];
        NSData *content;
        if (method == 0) {
            content = [data subdataWithRange:NSMakeRange(start, compressedSize)];
        } else if (method == 8) {
            NSMutableData *out = [NSMutableData dataWithLength:size];
            size_t written = size == 0 ? 0 : compression_decode_buffer(out.mutableBytes, size, b + start, compressedSize,
                                                                         NULL, COMPRESSION_ZLIB); // raw DEFLATE
            if (written != size) return [self fail:@"deflate" error:error];
            content = out;
        } else {
            return [self fail:[NSString stringWithFormat:@"method %lu", (unsigned long)method] error:error];
        }
        entries[name] = content;
    }
    return entries;
}

@end
