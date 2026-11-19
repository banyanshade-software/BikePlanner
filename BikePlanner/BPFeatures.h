//
//  BPFeatures.h
//  BikePlanner
//
//  Features that can be left out of a build at compile time.
//

#ifndef BPFeatures_h
#define BPFeatures_h

// File ▸ Send to Garmin Connect… and the toolbar button "Garmin" (#79): a sheet that automates the course import on
// the Garmin Connect web site, in the user's session, with the login kept in the Keychain. Garmin's Terms of Use make
// it a gray zone for a distributed app (#20, comment of 2026-11-19). 0: no menu item, no toolbar button (removed from
// the window), no code of the sheet nor of the Keychain item in the binary. Can also be set in the build settings
// (GCC_PREPROCESSOR_DEFINITIONS: BP_GARMIN_CONNECT=0).
#ifndef BP_GARMIN_CONNECT
#define BP_GARMIN_CONNECT 1
#endif

#endif /* BPFeatures_h */
