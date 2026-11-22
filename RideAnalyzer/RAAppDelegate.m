//
//  RAAppDelegate.m
//  RideAnalyzer
//

#import "RAAppDelegate.h"
#import "RALibraryWindowController.h"

@implementation RAAppDelegate

+ (NSMenuItem *)item:(NSString *)title action:(nullable SEL)action key:(NSString *)key
{
    return [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
}

+ (NSMenuItem *)submenu:(NSMenu *)menu
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:menu.title action:NULL keyEquivalent:@""];
    item.submenu = menu;
    return item;
}

+ (NSMenu *)mainMenu
{
    NSString *appName = [NSProcessInfo processInfo].processName;
    NSMenu *main = [[NSMenu alloc] initWithTitle:@"Main"];

    NSMenu *app = [[NSMenu alloc] initWithTitle:appName];
    [app addItem:[self item:[NSString stringWithFormat:NSLocalizedString(@"About %@", @"menu"), appName]
                     action:@selector(orderFrontStandardAboutPanel:) key:@""]];
    [app addItem:[NSMenuItem separatorItem]];
    NSMenuItem *services = [self item:NSLocalizedString(@"Services", @"menu") action:NULL key:@""];
    services.submenu = [[NSMenu alloc] initWithTitle:services.title];
    NSApp.servicesMenu = services.submenu;
    [app addItem:services];
    [app addItem:[NSMenuItem separatorItem]];
    [app addItem:[self item:[NSString stringWithFormat:NSLocalizedString(@"Hide %@", @"menu"), appName]
                     action:@selector(hide:) key:@"h"]];
    NSMenuItem *hideOthers = [self item:NSLocalizedString(@"Hide Others", @"menu")
                                 action:@selector(hideOtherApplications:) key:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [app addItem:hideOthers];
    [app addItem:[self item:NSLocalizedString(@"Show All", @"menu") action:@selector(unhideAllApplications:) key:@""]];
    [app addItem:[NSMenuItem separatorItem]];
    [app addItem:[self item:[NSString stringWithFormat:NSLocalizedString(@"Quit %@", @"menu"), appName]
                     action:@selector(terminate:) key:@"q"]];
    [main addItem:[self submenu:app]];

    NSMenu *file = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"File", @"menu")];
    [file addItem:[self item:NSLocalizedString(@"New Library", @"menu") action:@selector(newDocument:) key:@"n"]];
    [file addItem:[self item:NSLocalizedString(@"Open Library…", @"menu") action:@selector(openDocument:) key:@"o"]];
    [file addItem:[NSMenuItem separatorItem]];
    [file addItem:[self item:NSLocalizedString(@"Close", @"menu") action:@selector(performClose:) key:@"w"]];
    [file addItem:[self item:NSLocalizedString(@"Save", @"menu") action:@selector(saveDocument:) key:@"s"]];
    [file addItem:[self item:NSLocalizedString(@"Revert to Saved", @"menu") action:@selector(revertDocumentToSaved:)
                         key:@""]];
    [file addItem:[NSMenuItem separatorItem]];
    NSMenuItem *import = [self item:NSLocalizedString(@"Import Files…", @"menu") action:@selector(importFiles:)
                                key:@"i"];
    import.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [file addItem:import];
    [file addItem:[self item:NSLocalizedString(@"Import from Device…", @"menu") action:@selector(importFromDevice:)
                         key:@""]];
    [file addItem:[self item:NSLocalizedString(@"Fetch from Garmin Connect…", @"menu")
                      action:@selector(fetchFromGarminConnect:) key:@""]];
    [file addItem:[self item:NSLocalizedString(@"Apply Garmin Connect Corrections", @"menu")
                      action:@selector(applyGarminCorrections:) key:@""]];
    [file addItem:[self item:NSLocalizedString(@"Get Rider Weights from Garmin Connect", @"menu")
                      action:@selector(updateWeighingsFromGarmin:) key:@""]];
    [main addItem:[self submenu:file]];

    NSMenu *edit = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"Edit", @"menu")];
    [edit addItem:[self item:NSLocalizedString(@"Undo", @"menu") action:@selector(undo:) key:@"z"]];
    NSMenuItem *redo = [self item:NSLocalizedString(@"Redo", @"menu") action:@selector(redo:) key:@"z"];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [edit addItem:redo];
    [edit addItem:[NSMenuItem separatorItem]];
    [edit addItem:[self item:NSLocalizedString(@"Cut", @"menu") action:@selector(cut:) key:@"x"]];
    [edit addItem:[self item:NSLocalizedString(@"Copy", @"menu") action:@selector(copy:) key:@"c"]];
    [edit addItem:[self item:NSLocalizedString(@"Paste", @"menu") action:@selector(paste:) key:@"v"]];
    NSMenuItem *del = [self item:NSLocalizedString(@"Delete", @"menu") action:@selector(delete:) key:@"\b"];
    del.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [edit addItem:del];
    [edit addItem:[self item:NSLocalizedString(@"Select All", @"menu") action:@selector(selectAll:) key:@"a"]];
    [edit addItem:[NSMenuItem separatorItem]];
    [edit addItem:[self item:NSLocalizedString(@"Find…", @"menu") action:@selector(focusSearch:) key:@"f"]];
    NSMenuItem *filter = [self item:NSLocalizedString(@"Filter…", @"menu") action:@selector(editFilter:) key:@"f"];
    filter.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [edit addItem:filter];
    [edit addItem:[self item:NSLocalizedString(@"Clear Filter", @"menu") action:@selector(clearFilter:) key:@""]];
    [edit addItem:[self item:NSLocalizedString(@"Save Filter…", @"menu") action:@selector(saveFilter:) key:@""]];
    [main addItem:[self submenu:edit]];

    NSMenu *window = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"Window", @"menu")];
    [window addItem:[self item:NSLocalizedString(@"Minimize", @"menu") action:@selector(performMiniaturize:) key:@"m"]];
    [window addItem:[self item:NSLocalizedString(@"Zoom", @"menu") action:@selector(performZoom:) key:@""]];
    [window addItem:[NSMenuItem separatorItem]];
    NSMenuItem *trends = [self item:NSLocalizedString(@"Trends", @"menu") action:@selector(showTrends:) key:@"t"];
    trends.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [window addItem:trends];
    NSMenuItem *map = [self item:NSLocalizedString(@"Map of the Rides", @"menu") action:@selector(showRidesMap:) key:@"m"];
    map.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [window addItem:map];
    NSMenuItem *climbs = [self item:NSLocalizedString(@"Climbs", @"menu") action:@selector(showClimbs:) key:@"k"];
    climbs.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [window addItem:climbs];
    NSMenuItem *equipment = [self item:NSLocalizedString(@"Equipment", @"menu") action:@selector(showEquipment:) key:@"e"];
    equipment.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [window addItem:equipment];
    [main addItem:[self submenu:window]];
    NSApp.windowsMenu = window;

    NSMenu *help = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"Help", @"menu")];
    [main addItem:[self submenu:help]];
    NSApp.helpMenu = help;
    return main;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    NSApp.mainMenu = [RAAppDelegate mainMenu];
}

// R15: the last library is reopened at launch (window restoration does it too); a new one only the first time
- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    NSURL *last = [NSDocumentController sharedDocumentController].recentDocumentURLs.firstObject;
    if (!last) return YES;
    [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:last display:YES
        completionHandler:^(NSDocument *document, BOOL alreadyOpen, NSError *error) {
            if (!document) [[NSDocumentController sharedDocumentController] newDocument:nil];
        }];
    return NO;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app
{
    return YES;
}

@end
