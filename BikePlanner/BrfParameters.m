//
//  BrfParameters.m
//  BikePlanner
//
//  Created by Daniel on 10/08/2025.
//

#import "BrfParameters.h"

@implementation BrfParameters

- (void) fetchBrf:(NSString *)brf
{
    if (!brf || (brf.length==0)) brf = @"trefkking";
    
    NSString *s = [NSString stringWithFormat:@"https://brouter.de/brouter/profiles2/trekking.brf", brf];
    NSURL *url = [NSURL URLWithString:s];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!data) return;
        NSString *brfContent = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self parseBRF:brfContent];
        });
    }];
    [task resume];
}

- (void)parseBRF:(NSString *)brf
{
    NSError *err;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"assign\\s+(\\w+)\\s*=\\s*([\\d\\.\\-]+)"
                                                                           options:0 error:&err];
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:brf options:0 range:NSMakeRange(0, brf.length)];
    
    NSMutableArray *params = [NSMutableArray array];
    for (NSTextCheckingResult *m in matches) {
        NSString *name = [brf substringWithRange:[m rangeAtIndex:1]];
        NSString *value = [brf substringWithRange:[m rangeAtIndex:2]];
        [params addObject:@{@"name": name, @"default": value}];
    }
    self.brfParams = params;
    [self showProfileEditor];
}

- (void) showProfileEditor
{
    NSMutableArray *overrides = [NSMutableArray array];
    for (ParamRow *row in self.paramRows) { // custom struct/class storing UI state
        if (row.overrideCheckbox.state == NSControlStateValueOn) {
            NSString *pair = [NSString stringWithFormat:@"%@=%@", row.name, row.valueField.stringValue];
            [overrides addObject:pair];
        }
    }
    NSString *extraParams = [overrides componentsJoinedByString:@"|"];
}
@end
