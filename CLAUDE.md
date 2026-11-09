# BikePlanner — notes for Claude

Native macOS app (Objective-C, AppKit, XIB) to plan bicycle routes: MapKit + OSM/Thunderforest tiles for display,
brouter.de for routing, Overpass for POIs, Google Street View in a `WKWebView`.

Read first:
- `doc/01-high-level-spec.md` — what the app does (functional requirements F1–F12, decisions, open questions)
- `doc/02-architecture.md` — how it is built, key flows, **known bugs and tech debt (§9)**
- `doc/03-distribution-constraints.md` — third-party service constraints, status of each prerequisite (app is personal for now)
- `doc/04-embedded-brouter.md` (on branch `brouter` only) — plan for a BRouter engine embedded in the app
- `doc/get_google_api_key.md` (getting the Street View key), `doc/google-maps-embed-facturation.md` (in French, for
  the owner: Google console settings so the key cannot be billed)

Work items are tracked as GitHub issues on `banyanshade-software/BikePlanner`.

## Build & test

One-time setup: `cp BikePlanner/Secret.h.example BikePlanner/Secret.h` (git-ignored; the build fails without it;
put a real Thunderforest key in it for the OSM+cycle map, optionally a Google Maps Embed API key for Street View, #49:
`GOOGLE_MAPS_API_KEY`, or `GOOGLE_API_KEY` as in the owner's `Secret.h`. The app checks the Google key at the first
Street View and falls back to the Google Maps web app if Google rejects it).
Only `BPSecrets.m` includes `Secret.h`: it stores the keys obfuscated (#51); use `+[BPSecrets thunderforestAPIKey]` /
`+googleMapsAPIKey`, never the macros, and never log a key.
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

Expected state: all tests pass; the `XCTExpectFailure` ones (known bugs) are reported as "expected failure" (none
left since #9 / #12 were fixed).

## Adding files to the Xcode project

Do not hand-edit `project.pbxproj`. Use:
```sh
scripts/xcode_add_files.py --target BikePlanner      --anchor MapController.m   BikePlanner/NewThing.m BikePlanner/NewThing.h
scripts/xcode_add_files.py --target BikePlannerTests --anchor BikePlannerTests.m BikePlannerTests/NewTests.m
scripts/xcode_add_files.py --target BikePlannerUITests --anchor BikePlannerUITests.m BikePlannerUITests/NewUITests.m
```
Resources (`.plist`, `.json`) go to the target's Resources build phase (e.g. `BikePlanner/RemarkableSites.plist`, the
list of start sites, #65). A file already in the project can be added to another target the same way (e.g. `BikePlannerTests/BPStubServer.m`
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
- A waypoint that ends a stage (#31) is a `BPStageEndLocation` (subclass of `CLLocation`) in
  `plan.waypointsLocations`: change waypoints through the `BikePlan` mutators (`replaceWaypointAtIndex:by:` keeps
  the stage end), never by rebuilding the array from coordinates.
- `NSLog` is used for diagnostics. `if ((0))` / `#if 0` blocks are the owner's way to keep disabled code —
  don't delete them unless the task is cleanup.
- User-facing strings via `NSLocalizedString`.
- No compiler or analyzer warning (#58: clean build of every target, `xcodebuild … analyze` clean): keep it so.
  Headers are `NS_ASSUME_NONNULL`, so pass a sender (`self`), not `nil`, when calling an `IBAction` from code, and
  declare `nullable` parameters, properties and results that accept nil; compare an `NSNumber *` to nil explicitly
  (`if (n != nil)`). Third-party code (`DCO/`): silence a warning locally with `#pragma clang diagnostic`.
- HTTP requests are built with `+[BPEnvironment requestWithURL:]` (sets the app's User-Agent
  `BikePlanner/<version> (build <n>; +<GitHub URL>)`, required by the OSM tile and Overpass policies); endpoints come
  from `BPEnvironment`. Route requests: one at a time (`MapController` cancels the previous one, #9).
- The stub does not validate what real services do with a request (e.g. Overpass QL semantics): when changing a
  query or request format, also check it once against the real service (curl from the shell, never with a key in
  the command output). An `around:<polyline>` Overpass clause returned nothing on real routes (#12).

## Tests conventions

- Unit tests: `BikePlannerTests/`, hosted in the app; shared data/helpers in `TestFixtures.h`
  (`BPOverrideDefaults`, `BPWaitUntil`, `BPSpin`, `BPLoc`…). UI tests: `BikePlannerUITests/`, base class `BPUITestCase`.
- **Everything runs offline.** External services are replaced by `BPStubServer` (in `BikePlannerTests/`, compiled
  into both test targets), which imitates BRouter (routes in GeoJSON — the app requests `format=geojson` since #53 —
  or GPX, `.brf` profiles; GeoJSON way tags: first half tertiary/asphalt, second half track/gravel), Overpass (3 POIs
  ~1 km from the first `around` point) and the Maps Embed API (HTTP 403 for a key starting with `invalid`, like Google
  for a rejected key). It records every request (path, query, body, `referer`, `userAgent`) — use the request log as
  the oracle. Failures: `failCount` / `failStatus` / `failRetryAfter`; slow answers: `responseDelay` (read when the
  request starts). `+geojsonForLonLats:` / `+gpxForLonLats:` give the route the stub returns.
  - unit tests: `[server startInProcess]` (NSURLProtocol, no socket — the sandboxed host app cannot listen), then
    point the app to it with `BPOverrideDefaults(@{ @"BPBRouterServer": server.baseURL.absoluteString, … })` and
    `BPRestoreDefaults()` in tearDown;
  - UI tests: `BPUITestCase` starts a real HTTP server (`[server start]`, needs `network.server`, granted to the UI test
    runner by `BikePlannerUITests.entitlements`) and passes launch arguments to the app.
- App-side test hooks are in `BPEnvironment` (`BPBRouterServer`, `BPOverpassURL`, `BPGoogleMapsEmbedURL`, `BPDisableStreetView`,
  `BPDisableTiles`, `BPInitialRegion`, `BPDisableLocation`, `BPRemarkableSiteIndex`); no effect without overrides. When adding an external endpoint, route it
  through `BPEnvironment` and teach `BPStubServer` to answer it. The Apple place search goes through `BPPlaceSearch`:
  tests replace it with `+setSearchHandlerForTesting:`. Tests of the Preferences use a private `NSUserDefaults`
  suite, never the owner's defaults. The test host reads the owner's real user defaults (Preferences, my default
  BRouter parameters): a test that depends on `BPDefaultPosition`, `BPInitialRadiusKm`, `BPStartPosition`, `BPProfileOverrides`… must
  override it with `BPOverrideDefaults`. `BPOverrideDefaults` is not cumulative: each call starts again from the
  original values, so a second call in a test drops the overrides of `setUp` — repeat them.
- Waiting: prefer `BPWaitUntil(timeout, condition)` to a fixed `BPSpin` for anything animated or asynchronous (map
  region animations made a test flaky). A cancelled request may still reach the in-process stub after the test:
  spin a little at the end of such a test so it does not consume the next test's `failCount`.
- `Secret.h` is not in the Xcode project: a test that needs it imports `"../BikePlanner/Secret.h"` and never prints
  the key (`SecretsTests`).
- XCTest macros: a comma inside a message send (`[NSString stringWithFormat:@"%@", x]`) splits the macro arguments —
  compute the value in a variable first.
- Integration tests of the window: `DocumentWindowTests` opens a real document window and drives `MapController`;
  map clicks go through `-handleMapClick:` with a fake gesture recognizer (`BPFakeClick`). A new document starts in
  Edit mode, a document opened from a file (`initWithContentsOfURL:`) in View mode (#56): switch to Edit before
  clicking to add waypoints. Route changes that keep the waypoints (*Recalculate Route*, #55) go through
  `requestRouteUndoable:`.
- Private methods are tested by declaring a category in the test file.
- Undo: in tests, the undo manager does not close its automatic groups in nested run loops — set
  `groupsByEvent = NO` and group explicitly (see `UndoTests`).
- UI tests: controls created in code have `accessibilityIdentifier`s (`map`, `clickMode`, `mapType`, `clickModeHelp`,
  `zoomIn`…, `profileZoomIn`/`profileZoomOut`/`profileZoomFit` (elevation profile, #62), `brf.<parameter>` in the Params tab, `routeRoadTypes` (Info section, a `BPRoadTypesView`: radio buttons `roadType.<kind>` / `roadType.none`, #66; selecting a
  road type or a surface highlights it on the map, #54), `poiType`/`poiName` (custom POI
  sheet), `prefLatitude`/`prefLongitude`/`prefRadius`/`prefSearch` (Preferences), `routeLength`/`routeAscent`/`routeTime`/`routeSpeed` in the XIB — on the cell: unit tests find them with
  `-[DocumentWindowTests panelControlWithIdentifier:]`). POI markers and callouts are not exposed to accessibility:
  check POI behavior through its effects (stub requests, undo menu items). Files exchanged with the app go in
  `/private/tmp/bp-uitests/`.
- A known, not-yet-fixed bug is documented with a test wrapped in `XCTExpectFailure(@"… (#issue)")`. When fixing
  the bug, remove the `XCTExpectFailure` — the test must then pass.
- Fix a bug = first a failing test, then the fix. No fix without test coverage of the code involved.

## Packaging

`scripts/make_dmg.sh` builds `build/BikePlanner-<version>.dmg` (see its header). Unless the owner says otherwise, a DMG is built only
from `main` or `dev` (after the batch branch is merged), never from a batch or feature branch: if the owner asks for
one on another branch, say so first. Its Finder layout step uses
AppleScript, which needs the owner's Automation permission for Finder and does not work from Claude's sandboxed
shell: let the owner run it (`! scripts/make_dmg.sh`). The DMG embeds the Thunderforest key (obfuscated, #51: the script refuses an app containing it in clear): don't
publish it.

## Running the app

The owner launches the app (`! open ".../Build/Products/Debug/BikePlanner.app"`); Claude's shell may not kill or
relaunch it. `open` on a running instance only brings it to the front: quit it first (⌘Q) to run a new build.
Diagnostics of a run: temporary `NSLog(@"DIAGxx …")`, then `/usr/bin/log show --last 5m --style compact
--predicate 'process == "BikePlanner" AND eventMessage CONTAINS "DIAGxx"'` (read-only; remove the logs before
committing). The Debug build is `~/Library/Developer/Xcode/DerivedData/BikePlanner-*/Build/Products/Debug/`.

## Workflow

- Branch `dev` for work, `main` is the default branch for PRs. A batch of issues may get its own branch (`v08`, `v09`…;
  current batch: `v10`, from `dev` at 0.9.2), merged into `dev` (then `main`) when the owner asks — usually a
  fast-forward. The owner builds the DMG (`scripts/make_dmg.sh`) after a merge. Branch `brouter`: embedded BRouter
  engine (long-running).
- The owner tests at the end of a batch; commit when the unit tests pass (if asked), push / close issues only when
  asked, with a closing comment giving the commit. Read the issue body and comments first (`gh issue view N` then
  `gh issue view N --comments`: with `--comments`, `gh` prints only the comments).
- Version: `MARKETING_VERSION` (2 lines of `project.pbxproj`, app target), bumped by the owner's request; the build
  number and commit are set at build time (`scripts/set_build_info.sh`).
- Docs, code comments, commit messages and issues are in **English**; the owner talks in French.
- Don't commit, push or create issues/PRs without being asked. Ask when in doubt about intended behavior —
  the spec's "open questions" list is the place to record it.
- Keep `doc/` up to date when behavior or architecture changes (and the §9 table when a bug is fixed or found).
