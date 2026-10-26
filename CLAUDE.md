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

```sh
# build the app
xcodebuild -project BikePlanner.xcodeproj -scheme BikePlanner -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build -quiet

# unit tests (≈ 1 min, no network needed)
xcodebuild -project BikePlanner.xcodeproj -scheme BikePlanner -destination 'platform=macOS,arch=arm64' \
  -only-testing:BikePlannerTests CODE_SIGNING_ALLOWED=NO test 2>&1 \
  | grep -E "Test case .*(failed|expected)|\*\* TEST"

# one test class / method
  -only-testing:BikePlannerTests/GPXParserTests[/testParsesTrackPointsWithElevation]
```
Failure details: add `-resultBundlePath <scratch>/r.xcresult`, then
`xcrun xcresulttool get test-results tests --path <scratch>/r.xcresult`.

UI tests (`BikePlannerUITests`) are Xcode templates, not maintained.

## Adding files to the Xcode project

Do not hand-edit `project.pbxproj`. Use:
```sh
scripts/xcode_add_files.py --target BikePlanner      --anchor MapController.m   BikePlanner/NewThing.m BikePlanner/NewThing.h
scripts/xcode_add_files.py --target BikePlannerTests --anchor BikePlannerTests.m BikePlannerTests/NewTests.m
```
New files go in the anchor's group/directory. Use `SupportClasses/` + `--anchor GPXParser.m` for support classes.
XIB files (`Document.xib`, `MainMenu.xib`, …) should be edited in Xcode by the owner when possible; if a change is
needed, keep it minimal and say so.

The targets `BikePlanner_org*` are leftovers from an earlier project: ignore them.

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

- Tests live in `BikePlannerTests/`, hosted in the app; shared data/helpers in `TestFixtures.h`.
- Private methods are tested by declaring a category in the test file (see `MapControllerGeometryTests.m`).
- **No network** in unit tests: set `plan.fetchPOI = NO` on any `BikePlan` used; don't call `requestRoute`.
- A known, not-yet-fixed bug is documented with a test wrapped in `XCTExpectFailure(@"…")`. When fixing the bug,
  remove the `XCTExpectFailure` — the test must then pass.
- Fix a bug = first a failing test, then the fix.

## Workflow

- Branch `dev` for work, `main` is the default branch for PRs.
- Docs, code comments, commit messages and issues are in **English**; the owner talks in French.
- Don't commit, push or create issues/PRs without being asked. Ask when in doubt about intended behavior —
  the spec's "open questions" list is the place to record it.
- Keep `doc/` up to date when behavior or architecture changes (and the §9 table when a bug is fixed or found).
