//
//  GPXParser.h
//  BikePlanner
//
//  Created by Daniel on 09/08/2025.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GPXParser : NSObject <NSXMLParserDelegate>

- (nullable NSArray<CLLocation *> *)parseGPXData:(NSData *)data error:(NSError * _Nullable *)error;
- (NSDictionary *)brouterInfo;
@end

NS_ASSUME_NONNULL_END
