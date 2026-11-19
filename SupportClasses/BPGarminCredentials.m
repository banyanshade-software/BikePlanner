//
//  BPGarminCredentials.m
//  BikePlanner
//
//  The Garmin Connect login kept by BikePlanner (#79).
//

#import "BPGarminCredentials.h"
#import <Security/Security.h>
#import <os/log.h>

static NSString *const BPGarminServer = @"sso.garmin.com";
static NSString *const BPGarminNeverSaveKey = @"BPGarminNeverSaveAccounts";

@implementation BPGarminKeychain

+ (instancetype)shared
{
    static BPGarminKeychain *k;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ k = [[self alloc] init]; });
    return k;
}

- (NSMutableDictionary *)query
{
    return [@{ (__bridge id)kSecClass: (__bridge id)kSecClassInternetPassword,
               (__bridge id)kSecAttrServer: BPGarminServer,
               (__bridge id)kSecAttrProtocol: (__bridge id)kSecAttrProtocolHTTPS } mutableCopy];
}

- (nullable NSDictionary<NSString *, NSString *> *)savedLogin
{
    NSMutableDictionary *q = [self query];
    q[(__bridge id)kSecReturnAttributes] = @YES;
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)q, &result);
    if (status != errSecItemNotFound) os_log(OS_LOG_DEFAULT, "Garmin: Keychain read, status %d", (int)status); // not the login
    if (status != errSecSuccess || !result) return nil;
    NSDictionary *item = (__bridge_transfer NSDictionary *)result;
    NSString *account = item[(__bridge id)kSecAttrAccount];
    NSData *data = item[(__bridge id)kSecValueData];
    NSString *password = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (!account.length || !password.length) return nil;
    return @{ @"account": account, @"password": password };
}

- (BOOL)saveAccount:(NSString *)account password:(NSString *)password
{
    [self forgetLogin]; // a single login
    NSMutableDictionary *q = [self query];
    q[(__bridge id)kSecAttrAccount] = account;
    q[(__bridge id)kSecValueData] = [password dataUsingEncoding:NSUTF8StringEncoding];
    q[(__bridge id)kSecAttrLabel] = @"BikePlanner – Garmin Connect";
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)q, NULL);
    os_log(OS_LOG_DEFAULT, "Garmin: login saved in the Keychain, status %d", (int)status); // not the login itself
    return status == errSecSuccess;
}

- (void)forgetLogin
{
    SecItemDelete((__bridge CFDictionaryRef)[self query]);
}

- (BOOL)isNeverSaved:(NSString *)account
{
    return [[[NSUserDefaults standardUserDefaults] stringArrayForKey:BPGarminNeverSaveKey] containsObject:account.lowercaseString];
}

- (void)setNeverSaved:(NSString *)account
{
    NSMutableArray *a = [[[NSUserDefaults standardUserDefaults] stringArrayForKey:BPGarminNeverSaveKey] mutableCopy] ?: [NSMutableArray array];
    if (![a containsObject:account.lowercaseString]) [a addObject:account.lowercaseString];
    [[NSUserDefaults standardUserDefaults] setObject:a forKey:BPGarminNeverSaveKey];
}

@end

@implementation BPGarminMemoryCredentials {
    NSDictionary<NSString *, NSString *> *_login;
    NSMutableSet<NSString *> *_never;
}

- (instancetype)init
{
    if (self = [super init]) _never = [NSMutableSet set];
    return self;
}

- (nullable NSDictionary<NSString *, NSString *> *)savedLogin { return _login; }
- (BOOL)saveAccount:(NSString *)account password:(NSString *)password { _login = @{ @"account": account, @"password": password }; return YES; }
- (void)forgetLogin { _login = nil; }
- (BOOL)isNeverSaved:(NSString *)account { return [_never containsObject:account.lowercaseString]; }
- (void)setNeverSaved:(NSString *)account { [_never addObject:account.lowercaseString]; }

@end
