# BikePlanner — notes for Claude

Native macOS app (Objective-C, AppKit, XIB) to plan bicycle routes: MapKit + OSM/Thunderforest tiles for display,
brouter.de for routing, Overpass for POIs, Google Street View in a `WKWebView`.

Read first:
- `doc/01-high-level-spec.md` — what the app does (functional requirements F1–F11, decisions, open questions)
- `doc/02-architecture.md` — how it is built, key flows, **known bugs and tech debt (§9)**
- `doc/03-distribution-constraints.md` — third-party service constraints (app is personal for now)

Work items are tracked as GitHub issues on `banyanshade-software/BikePlanner`.

## Build & test

One-time setup: `cp BikePlanner/Secret.h.example BikePlanner/Secret.h` (git-ignored; the build fails without it;
put a real Thunderforest key in it for the OSM+cycle map).
UI tests also need macOS Automation Mode, enabled once by the owner in Terminal.app:
`sudo automationmodetool enable-automationmode-without-authentication` (`automationmodetool` shows the status).

No signing identity on this machine: sign ad hoc. Signing applies the entitlements (app sandbox), as Xcode's ⌘U does.
```sh
SIGN="CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="
DEST="-destination platform=macOS,arch=arm64"

# build the app
xcodebuild -project BikePlanner.xcodeproj -scheme BikePlanner $DEST $SIGN build -quiet

# unit tests (≈ 2 min, offline)
xcodebuild -project BikePlanner.xcodeproj -scheme BikePlanner $DEST $SIGN -only-testing:BikePlannerTests test 2>&1 \
  | grep -E "Test case .*(failed|expected)|\*\* TEST"

# UI tests (≈ 4 min, offline; they take control of the mouse and keyboard — tell the owner before running)
xcodebuild ... -only-testing:BikePlannerUITests test

# everything + coverage
xcodebuild ... -enableCodeCoverage YES -resultBundlePath <scratch>/r.xcresult test
xcrun xccov view --report --files-for-target BikePlanner.app <scratch>/r.xcresult

# one test class / method
  -only-testing:BikePlannerTests/GPXParserTests[/testParsesTrackPointsWithElevation]
```
(in zsh, `$SIGN`/`$DEST` are not word-split: write the options out, or use `${=SIGN}`.)
Failure details: add `-resultBundlePath <scratch>/r.xcresult`, then
`xcrun xcresulttool get test-results tests --path <scratch>/r.xcresult`.

Expected state: all tests pass; the `XCTExpectFailure` ones (known bugs) are reported as "expected failure".

## Adding files to the Xcode project

Do not hand-edit `project.pbxproj`. Use:
```sh
scripts/xcode_add_files.py --target BikePlanner      --anchor MapController.m   BikePlanner/NewThing.m BikePlanner/NewThing.h
scripts/xcode_add_files.py --target BikePlannerTests --anchor BikePlannerTests.m BikePlannerTests/NewTests.m
scripts/xcode_add_files.py --target BikePlannerUITests --anchor BikePlannerUITests.m BikePlannerUITests/NewUITests.m
```
A file already in the project can be added to another target the same way (e.g. `BikePlannerTests/BPStubServer.m`
is in both test targets). Removing a file: delete its lines from `project.pbxproj` (grep its name).
A Run Script phase: `scripts/xcode_add_run_script.py --target … --name … --script …` (see its header).
New files go in the anchor's group/directory. Use `SupportClasses/` + `--anchor GPXParser.m` for support classes.
XIB files (`Document.xib`, `MainMenu.xib`, …) should be edited in Xcode by the owner when possible; if a change is
needed, keep it minimal and say so.
A target is removed with `scripts/xcode_remove_target.py <target name>…` (its phases, configurations, dependencies
and product; source files are kept).

## Code conventions

- Objective-C with ARC, `NS_ASSUME_NONNULL_BEGIN/END` in headers, 4-space indentation, braces on the next line
  for methods, same line for control flow. Match the style of the file you edit.
- Ivars in `@implementation { … }`, private methods are not declared in headers.
- UI and model changes happen on the main thread; network completions must `dispatch_async` to the main queue.
- Every user-visible change of the plan must be undoable and/or mark the document edited
  (`undoableWP:desc:` in `MapController` for waypoints).
- `NSLog` is used for diagnostics. `if ((0))` / `#if 0` blocks are the owner's way to keep disabled code —
  don't delete them unless the task is cleanup.
- User-facing strings via `NSLocalizedString`.

## Tests conventions

- Unit tests: `BikePlannerTests/`, hosted in the app; shared data/helpers in `TestFixtures.h`
  (`BPOverrideDefaults`, `BPWaitUntil`, `BPSpin`, `BPLoc`…). UI tests: `BikePlannerUITests/`, base class `BPUITestCase`.
- **Everything runs offline.** External services are replaced by `BPStubServer` (in `BikePlannerTests/`, compiled
  into both test targets), which imitates BRouter (route GPX, `.brf` profiles) and Overpass (3 POIs ~1 km from the
  route start) and records every request — use the request log as the oracle.
  - unit tests: `[server startInProcess]` (NSURLProtocol, no socket — the sandboxed host app cannot listen), then
    point the app to it with `BPOverrideDefaults(@{ @"BPBRouterServer": server.baseURL.absoluteString, … })` and
    `BPRestoreDefaults()` in tearDown;
  - UI tests: `BPUITestCase` starts a real HTTP server (`[server start]`, needs `network.server`, granted to the UI test
    runner by `BikePlannerUITests.entitlements`) and passes launch arguments to the app.
- App-side test hooks are in `BPEnvironment` (`BPBRouterServer`, `BPOverpassURL`, `BPDisableStreetView`,
  `BPDisableTiles`, `BPInitialRegion`, `BPDisableLocation`); no effect without overrides. When adding an external endpoint, route it
  through `BPEnvironment` and teach `BPStubServer` to answer it. The Apple place search goes through `BPPlaceSearch`:
  tests replace it with `+setSearchHandlerForTesting:`. Tests of the Preferences use a private `NSUserDefaults`
  suite, never the owner's defaults.
- Integration tests of the window: `DocumentWindowTests` opens a real document window and drives `MapController`;
  map clicks go through `-handleMapClick:` with a fake gesture recognizer (`BPFakeClick`).
- Private methods are tested by declaring a category in the test file.
- Undo: in tests, the undo manager does not close its automatic groups in nested run loops — set
  `groupsByEvent = NO` and group explicitly (see `UndoTests`).
- UI tests: controls created in code have `accessibilityIdentifier`s (`map`, `clickMode`, `mapType`, `clickModeHelp`,
  `zoomIn`…, `brf.<parameter>` in the Params tab, `routeLength`/`routeAscent`/`routeTime`/`routeSpeed` in the XIB — on the cell: unit tests find them with
  `-[DocumentWindowTests panelControlWithIdentifier:]`). POI markers and callouts are not exposed to accessibility:
  check POI behavior through its effects (stub requests, undo menu items). Files exchanged with the app go in
  `/private/tmp/bp-uitests/`.
- A known, not-yet-fixed bug is documented with a test wrapped in `XCTExpectFailure(@"… (#issue)")`. When fixing
  the bug, remove the `XCTExpectFailure` — the test must then pass.
- Fix a bug = first a failing test, then the fix. No fix without test coverage of the code involved.

## Packaging

`scripts/make_dmg.sh` builds `build/BikePlanner-<version>.dmg` (see its header). Its Finder layout step uses
AppleScript, which needs the owner's Automation permission for Finder and does not work from Claude's sandboxed
shell: let the owner run it (`! scripts/make_dmg.sh`). The DMG embeds the Thunderforest key: don't publish it.

## Workflow

- Branch `dev` for work, `main` is the default branch for PRs.
- Docs, code comments, commit messages and issues are in **English**; the owner talks in French.
- Don't commit, push or create issues/PRs without being asked. Ask when in doubt about intended behavior —
  the spec's "open questions" list is the place to record it.
- Keep `doc/` up to date when behavior or architecture changes (and the §9 table when a bug is fixed or found).
