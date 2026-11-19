//
//  BPGarminCredentials.h
//  BikePlanner
//
//  The Garmin Connect login kept by BikePlanner (#79, owner's choice 2026-11-19): captured on the Garmin login page
//  when the user logs in, kept in the user's login Keychain if the user agrees, then filled in the page the next
//  times (the user still clicks "Se connecter"). Safari's saved passwords cannot be reached by a third-party app.
//  Never logged nor saved in a document.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol BPGarminCredentialStore <NSObject>
/// the saved login: @{ @"account": …, @"password": … }; nil if none
- (nullable NSDictionary<NSString *, NSString *> *)savedLogin;
- (BOOL)saveAccount:(NSString *)account password:(NSString *)password;
- (void)forgetLogin;
/// accounts the user does not want to save ("Never for this account")
- (BOOL)isNeverSaved:(NSString *)account;
- (void)setNeverSaved:(NSString *)account;
@end

/// the login Keychain (internet password of sso.garmin.com, label "BikePlanner – Garmin Connect"); the "never"
/// accounts in the user defaults (BPGarminNeverSaveAccounts)
@interface BPGarminKeychain : NSObject <BPGarminCredentialStore>
+ (instancetype)shared;
@end

/// tests: in memory, never the user's Keychain
@interface BPGarminMemoryCredentials : NSObject <BPGarminCredentialStore>
@end

NS_ASSUME_NONNULL_END
