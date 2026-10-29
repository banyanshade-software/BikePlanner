# BikePlanner — Architecture

Status: **describes the code as it is** (branch `dev`, October 2026). Companion to
[01-high-level-spec.md](01-high-level-spec.md). Section 9 lists the technical debt and risks found while
writing this document; it is the starting point for the reliability work.

---

## 1. Overview

BikePlanner is a classic **AppKit document-based application** written in Objective-C (ARC), with the UI
in XIB files. There is no third-party dependency manager: everything uses Apple frameworks
(AppKit, MapKit, CoreLocation, WebKit, Foundation networking).

```
                    +--------------------+
                    |  NSDocumentController (AppKit)
                    +---------+----------+
                              | one per window
                    +---------v----------+        owns        +-------------+
                    |      Document      |------------------->|  BikePlan   |  (model, persisted)
                    |   (NSDocument)     |                    +------+------+
                    +---------+----------+                           | Overpass (POI)
                              | File's Owner of Document.xib         v
       +----------------------+-------------------------+     overpass-api.de
       |                      |                         |
+------v---------+   +--------v-----------+   +---------v--------------+
| PlannerWindow- |   |   MapController    |   | StreetViewController   |
| Controller     |   | (MKMapViewDelegate)|-->| (WKWebView)            |--> google.com/maps
+------+---------+   +---+-----+-----+----+   +------------------------+
       |                 |     |     |
       v                 |     |     +--> ElevationProfileView (custom NSView, delegate = MapController)
 BRFProfileEditor        |     +--------> BRouterClient --> brouter.de  --> GPXParser
 (NSViewController)      +--------------> MKMapView (BikeMapView) + tile overlays (OSM / Thunderforest)
   --> brouter.de/profiles2
```

`MapController` is the central controller: it owns almost all of the interaction logic (≈1 700 lines).

## 2. Source tree

```
BikePlanner/                 App target
  main.m, AppDelegate.*      App entry, About window, Preferences menu
  BPPreferences.*            Typed user settings (default position, initial radius; #27)
  BPPreferencesWindowController.*  Preferences window, built in code
  Document.*                 NSDocument subclass: load/save, menu relays
  PlannerWindowController.*  Window setup, wires MapController / StreetView / BRF editor
  MapController.*            Map interaction, route requests, annotations, export, undo
  BikePlan.*                 Model: waypoints, route, POIs, reference trace; POI fetching
  ExportAccessoryView*       Accessory view of the GPX save panel ("include POI" checkbox)
  Base.lproj/Document.xib    Document window (split views, map, tabs, profile, toolbar)
  Base.lproj/MainMenu.xib    Menus
  Secret.h.example           Template for Secret.h (Thunderforest API key, git-ignored)
  BPSecrets.*                The only includer of Secret.h: keys XOR-ed at compile time, decoded at run time (#51)
  Assets.xcassets            App icon, POI icons (SVG from mapbox/maki)
SupportClasses/              Reusable/support components
  BRouterClient.*            HTTP client for BRouter
  GPXParser.*                NSXMLParser-based GPX reader + BRouter comment parser; minimal GPX writer
  BRouterGeoJSON.*           BRouter route in GeoJSON: points, statistics, distance by road / surface class (#53)
  BPPlaceSearch.*            Apple place search (MKLocalSearch), shared by the search field and the Preferences
  BPPOIEditor.*              Sheet asking the type and name of a custom POI (#3)
  BRFProfileEditor.*         Downloads a .brf profile, parses its annotated parameters, builds the Params tab UI;
                             "my defaults" (user defaults BPProfileOverrides)
  ElevationProfileView.*     Elevation chart, scrubbing
  StreetViewController.*     Loads Google Street View URLs into a WKWebView
  POILocation.*              Model class for a POI (CLLocation subclass, NSSecureCoding)
  POIAnnotation.*            MKPointAnnotation for POIs, icon configuration
  POIAnnotationView.*        MKMarkerAnnotationView subclass (highlight color)
  POICalloutView.*           Callout content (tags + Include/Exclude)
  RouteAnnotation.*          MKPointAnnotation for waypoints (carries its index)
  TaggedPoly.*               MKPolyline with a tag (0 route, 1 waypoints, 2 reference GPX)
  SafeOSMTileOverlay.*, SafeTileRenderer.*   MKTileOverlay/Renderer subclasses (custom code disabled with #if 0)
  BikeMapView.*              MKMapView subclass (currently empty)
BSSUI/, DCO/                 Third-party / older own code for the About window (DCOAboutWindow, MIT-like LICENSE)
BikePlannerTests/, BikePlannerUITests/   Xcode template tests (empty)
testurl.sh                   Manual curl experiments against brouter.de
README.POI.GARMIN.txt        List of Garmin POI types usable in GPX <type>
```

## 3. Object graph and lifecycle

1. `NSDocumentController` creates a `Document` (new or from file). `-[Document init]` creates an empty `BikePlan`;
   `readFromData:ofType:error:` replaces it with the unarchived one.
2. `-[Document makeWindowControllers]` creates a `PlannerWindowController` loading `Document.xib`
   **with the Document as File's Owner**.
3. `Document.xib` instantiates as top-level objects: `MapController`, `StreetViewController`, and the views.
   Outlets: `Document.mapController`, `Document.brfParamsPlaceholder`, `MapController.{mapView, document, svCtrl, elevationView}`,
   `StreetViewController.webView`. Bindings: Info section labels → `plan.brouterInfo.kmlen` / `plan.brouterInfo.mup` /
   `plan.brouterInfo.durationText` / `plan.brouterInfo.averageSpeedText`;
   “Fetch POI” → `plan.fetchPOI`; “View POI” → `mapController.viewPOI`; Export toolbar item enabled ↔ `mapController.gpxData`.
4. `-[PlannerWindowController windowDidLoad]` asserts the wiring, then calls
   `-[MapController initializeMapview]`, `-[StreetViewController initializeStreetView]`,
   `-[MapController fullRefresh:YES]` and builds the `BRFProfileEditor` into the *Params* tab.
5. `initializeMapview` creates tile overlays, the `BRouterClient`, the overlay controls (buttons and segmented
   controls are created **in code**, added to the map's superview), the click gesture recognizer, the scrubber
   annotation, the mouse tracking area, and sets `plan.poiAvailableCallback`.

Menu actions (*Edit ▸ Mode…*, *Edit ▸ Reverse Route*, *Import*, *Export*) go through the responder chain to
`Document`, which relays them to `MapController` (`Document.validateMenuItem:` enables *Reverse Route* with ≥ 2
waypoints).

## 4. Data model

### 4.1 `BikePlan` (NSSecureCoding)

| Property | Type | Persisted key | Meaning |
|---|---|---|---|
| `waypointsLocations` | `NSArray<CLLocation*>` (immutable, replaced on each change) | `waypointsLocations` | User waypoints, ordered |
| `routePoints` | `NSArray<CLLocation*>` | `routePoints` | Route returned by BRouter, with altitude |
| `gpxDisplayed` | `NSArray<CLLocation*>` | `gpxDisplayed` | Reference trace |
| `brouterInfo` | `BrouterInfo` (`kmlen`, `mup`, `meters`, `seconds`) | `brouterInfo` | Length (km, m), ascent (m), riding time (s) estimated by BRouter; `meters`/`seconds` are 0 in documents saved before #30 |
| `poiloc` | `NSArray<POILocation*>` | `poiloc` | Fetched POIs |
| `customPoiloc` | `NSMutableArray<POILocation*>` | `customPoiloc` | User POIs |
| `excludedPOIKeys` | `NSSet<NSString*>` | `excludedPOIKeys` | POIs excluded from the export (callout Include/Exclude), by `POILocation.poiKey` (#5) |
| `routeGPX` | `NSData` | `routeGPX` | Raw BRouter GPX of the route, for the export; missing in older documents (export then generated from `routePoints`) (#10) |
| `profileOverrides` | `NSDictionary<NSString*,NSString*>` | `profileOverrides` | BRouter parameters (Params tab, name → value); missing in older documents = `@{}` (#44) |
| `fetchPOI` | `BOOL` | *not persisted* | Enables Overpass fetching |
| `routePoly`, `waypointPoly`, `gpxDisplayedPoly` | `TaggedPoly` | derived, cached | MapKit overlays built from the arrays |
| `poiAvailableCallback` | block | — | Called on main thread when POIs arrive |

Waypoint mutators (`appendWaypoint:`, `insertWaypoint:atIndex:`, `replaceWaypointAtIndex:by:`,
`removeWaypointAtIndex:`, `removeWaypoints`) **return the previous array**, which the controller registers for undo.

`BikePlan` also contains the **POI fetching logic** (Overpass query building, throttling with a retry
`NSTimer`, JSON parsing) — see §6.3.

### 4.2 `POILocation`
`CLLocation` subclass adding `poiType` (`PoiType_t` enum: unknown, drinking_water, toilets,
bicycle_repair_station, cemetery, warning), `info` (raw OSM tags), `userAdded`. Derives `title`,
`gpxSymbol`, `gpxType` (Garmin type) from the type. Persists `poitype` and `info`
(`userAdded` and `selectedForExport` are **not** persisted).

### 4.3 File format
`.bikeplan` = `NSKeyedArchiver` binary plist of the root `BikePlan`, with `requiringSecureCoding:YES`.
No version key: adding/removing fields relies on `decodeObject…` returning nil for missing keys.

### 4.4 State held outside the model (in `MapController`)
`gpxData` (GPX to export, bound to the Export toolbar item; kept in sync with `plan.exportableGPX`), click mode, map type,
`waypointsRouteAnnotations` (annotation per waypoint, kept in sync manually), `viewPOI`. None of this is persisted.

## 5. Map layer

- **Overlays**: tile overlays (`SafeOSMTileOverlay`, `canReplaceMapContent = YES`) for OSM / Thunderforest;
  `TaggedPoly` overlays for route (tag 0, blue, 8 px) and reference trace (tag 2, orange, 6 px).
  `rendererForOverlay` picks the renderer by class and tag. Switching to an Apple map type removes the tile overlay
  and sets `mapView.mapType`.
- **Annotations**: `RouteAnnotation` → `MKPinAnnotationView` (draggable, right-click menu), `POIAnnotation` →
  `POIAnnotationView` with `POICalloutView`, `MKPointAnnotation` for the scrubber and search results.
- **Hit testing**: done manually in screen space: nearest POI within a radius (`nearestPOIToScreenPoint:`),
  nearest point on the route polyline within a pixel tolerance (`nearestCoordinateOnPolyline:…`).
- **Insertion index** of an intermediate waypoint: projected distance along the route of the click vs. of each
  waypoint (`insertionIndexForCoordinate:polyline:waypoints:`), clamped so start and end stay first/last.
- **Refresh strategy**: `fullRefresh:` removes all non-tile overlays and rebuilds annotations, POIs, route,
  reference trace and profile from the model. Incremental updates are done in the click handlers.

## 6. Key flows

### 6.1 Add a destination (Edit mode)
```
NSClickGestureRecognizer → MapController.handleMapClick:
  ├─ near POI? → select annotation, stop
  ├─ near route? → insert intermediate waypoint (6.2)
  └─ else: plan.appendWaypoint → undoableWP:(old) ; add RouteAnnotation ; svCtrl.viewCoord
          → shouldRecalcRoute → requestRoute (6.4)
```

### 6.2 Insert / move / remove waypoint
Insert: `insertionIndexForCoordinate` → `plan.insertWaypoint` → undo → annotation insert + reindex → `requestRoute`.
Move: `mapView:annotationView:didChangeDragState:` (Ending) → `plan.replaceWaypointAtIndex` → undo → `requestRoute`.
Remove: context menu → `plan.removeWaypointAtIndex` → undo → reindex → `shouldRecalcRoute`.
Reverse: *Edit ▸ Reverse Route* → `plan.reverseWaypoints` → undo → `fullRefresh:NO` → `shouldRecalcRoute`.
Clear: *Edit ▸ Clear Route* → confirmation sheet (`NSAlert`) → `setRouteState:nil` → `plan.clearRoute` (returns the previous state, + BRouter GPX)
→ undo registers `undoRouteState:` with it → `fullRefresh:NO`; undo calls `plan.restoreRoute:` (no new request).
Import GPX as route: *File ▸ Import GPX as Route…* → `loadGPXAsRouteFromURL:` → `GPXParser` (`traceSource`,
`waypointTypes`) → `+[BikePlan waypointsForTrace:]` (track only) → confirmation sheet if the plan is not empty →
`setRouteFromTrace:…` in one undo group: `setRouteState:nil` (undo restores the previous route), waypoints, custom
POIs, `setGpxDisplayed:` (reference trace) → `shouldRecalcRoute`.

### 6.3 POIs
```
plan.routePoly getter → shouldRequestPOI (tpoineed = now) → tryRequestPoi
  ├─ fetchPOI off, <2 points, or already fetched → stop
  ├─ request in progress or last request < 2.8 s ago → (re)arm 2 s repeating NSTimer, stop
  └─ fetchPOIsNearRoute: POST Overpass QL (every 10th route point, radius 1500 m)
        error/HTTP≥300 → retry after 2 s
        success → main queue: build POILocation[] → plan.poiloc → poiAvailableCallback → MapController.refreshPOI
```

### 6.4 Route computation
Params tab Apply → `PlannerWindowController setProfileOverrides:` (undoable; sets `plan.profileOverrides` and
`brfEditor.appliedOverrides`) → `shouldRecalcRoute`.
```
MapController.requestRoute
  gpxData = nil
  BRouterClient.routeWithWaypoints:profile:plan.profileName overrides:plan.profileOverrides   (URL: +routeURLForServer:…)
    GET https://brouter.de/brouter?lonlats=lon,lat|lon,lat…&profile=trekking&alternativeidx=0&format=geojson[&profile:<name>=<value>…]
    (names and values percent-encoded, including & = + |; true/false sent as 1/0)
    (background) BRouterGeoJSON → points + brouterInfo (track-length, filtered ascend, total-time) + distance by road /
                 surface class (properties.messages: Distance + WayTags) (#53); the GPX for the export is generated
                 from the points (+[GPXParser gpxDataForPoints:name:comment:], BRouter statistics in the comment)
  completion (background) → error: NSLog only
                          → main queue: plan.brouterInfo.{kmlen,mup,meters,seconds,roadStats,surfaceStats}, gpxData, plan.routePoints,
                            elevationView.setGpxPoints, refreshPoly:NO (→ routePoly → POI flow 6.3)
```

### 6.5 Scrubbing (profile ↔ map ↔ Street View)
`ElevationProfileView` mouse down/drag → delegate `elevationProfileView:didSelectDistance:` →
`coordinateAtDistance:` + `bearingAtDistance:` → scrubber marker, map center, `svCtrl viewCoord:lookingAt:`.
Reverse direction (View mode click on route): `distanceAtCoordinate:` → `elevationView.highlightDistance`.

### 6.6 Undo / redo
`undoableWP:desc:` registers `undoAction:` with the **previous waypoint array** on the document's undo manager.
`undoAction:` registers the current array (for redo), restores the old one via `plan.undoSetWayPt:`,
then `fullRefresh:NO` and recomputes the route.
Custom POIs (`addCustomPoiAt:` / `undoCustomPoi:`) and the reference trace (`setGpxDisplayed:desc:`) follow the same
pattern with their own snapshot. Registering an undo action is also what marks the document as edited.

### 6.7 Save / load
`dataOfType:` / `readFromData:` archive/unarchive `BikePlan` (see 4.3). After load, the window controller's
`fullRefresh:YES` rebuilds the map and zooms to the route.

### 6.8 GPX export
`exportGPX:` → `NSSavePanel` + `ExportAccessoryViewController` → `exportGpxDataWithPOI:trackName:` which takes the
**raw BRouter GPX** (`gpxData`), replaces the first `<name>` with the file name, and inserts `<wpt>` elements
before `</gpx>` by string manipulation.

## 7. Threading model

- All UI and model mutation is intended to happen on the **main thread**.
- `NSURLSession` completions (BRouter, Overpass, BRF profile) run on background queues and hop to the main queue
  with `dispatch_async(dispatch_get_main_queue(), …)` before touching UI/model — with some exceptions noted in §9.
- No cancellation of in-flight requests; no request identifiers.

## 8. Build & configuration

- Xcode project `BikePlanner.xcodeproj`, scheme `BikePlanner`, targets: app, unit tests, UI tests (the leftover
  `BikePlanner_org*` targets of an earlier project were removed, #18).
- DMG: `scripts/make_dmg.sh` (Release build, ad hoc signed, or `--app <path>`) → `build/BikePlanner-<version>.dmg`
  (`build/` is git-ignored). The Finder window shows a background drawn at packaging time by
  `packaging/dmg/make_background.swift` with the app's version (1x + 2x PNG merged into a multi-resolution TIFF;
  the script also defines the icon positions), the app, a link to `/Applications` and an arrow. The volume and the
  `.dmg` file get the app icon. The layout is set with AppleScript (Finder automation permission needed; it
  does not work from a sandboxed shell). Not notarized, and it embeds the Thunderforest key of `Secret.h`
  (obfuscated; the script stops if the key is found in clear in the binaries).
- Tests (see `CLAUDE.md` for commands and conventions):
  - unit tests `BikePlannerTests` (hosted in the app) — model, parsing, geometry, export, network clients, panels,
    and integration tests of a real document window (`DocumentWindowTests`);
  - UI tests `BikePlannerUITests` (XCUITest, base class `BPUITestCase`) — end-to-end scenarios on the running app;
  - everything offline: `BPStubServer` imitates BRouter and Overpass (in-process `NSURLProtocol` for unit tests,
    local HTTP server for UI tests) and records requests;
  - known bugs are documented by tests wrapped in `XCTExpectFailure`.
  Coverage of the app target (October 2026): 86 % of lines; below 80 %: `AppDelegate` (debug run-loop loggers),
  `Document` (exception paths), third-party About window code.
- **Test hooks** — `BPEnvironment` reads endpoints and switches from `NSUserDefaults`, so that launch arguments
  can override them: `-BPBRouterServer <url>`, `-BPOverpassURL <url>`, `-BPDisableStreetView YES`,
  `-BPDisableTiles YES`, `-BPInitialRegion lat,lon,span` (region for a plan without route, instead of the user
  location), `-BPDisableLocation YES` (never ask for the user location). Defaults are the production endpoints.
  `BPEnvironment` also reads two real settings: `BPDefaultPosition` and `BPInitialRadiusKm` (initial region, F1.5). The app does not open an untitled document when it hosts unit tests.
  Accessibility identifiers are set on the map and on the controls created in code.
- UI test runner entitlements (`BikePlannerUITests/BikePlannerUITests.entitlements`): `network.server` for the stub
  server, read-write in `/private/tmp/` to exchange files with the app.
- New source files are added to the project with `scripts/xcode_add_files.py`, Run Script phases with
  `scripts/xcode_add_run_script.py`.
- Build info: the *Set build info* Run Script phase of the app target (`scripts/set_build_info.sh`, runs on every
  build, after Copy Bundle Resources) writes into the **built** Info.plist `CFBundleVersion` = number of commits,
  `BPGitCommit` = short hash (+ `-dirty`), `BPGitBranch`; no-op without git. `MARKETING_VERSION` stays manual.
  `+[AppDelegate versionStringWithInfo:]` formats the About window version.
- macOS deployment target 12.7, ARC on.
- **Before building**: copy `BikePlanner/Secret.h.example` to `BikePlanner/Secret.h` and set `THUNDERFOREST_API_KEY`
  (the build fails without `Secret.h`).
- Entitlements: App Sandbox, user-selected files read/write, outgoing network, location.
- Endpoints: BRouter and Overpass come from `BPEnvironment`; the Google Street View and tile URLs are still
  hard-coded in `StreetViewController.m` and `MapController.m`.
- Logging: `NSLog` everywhere, quite verbose (e.g. per-segment logs in `bearingAtDistance:`).

## 9. Technical debt, risks and suspected bugs

Findings from reading the code; those marked ✅ are confirmed by a unit test. Severity: **H** high, **M** medium, **L** low.
Each item is tracked as a GitHub issue.

### Correctness
| # | Sev | Where | Finding | Issue |
|---|---|---|---|---|
| 1 | M ✅ fixed | `BikePlan.m` `routePoly` | `routePoly` tested `!_waypointPoly` instead of `!_routePoly`: the route polyline was rebuilt, and the POIs re-requested, at each access. Now cached and invalidated by `setRoutePoints:` (`testRoutePolyIsCached`). | [#6](https://github.com/banyanshade-software/BikePlanner/issues/6) |
| 2 | H ✅ fixed | `POIAnnotation.h:16`, `POICalloutView.h:14` | `info` / `infodic` are `assign` object properties (= `unsafe_unretained` under ARC) → potential dangling pointer / crash. | [#7](https://github.com/banyanshade-software/BikePlanner/issues/7) |
| 3 | H ✅ fixed | `MapController.m:523`, `MapController.m:1640` | Adding a custom POI or importing a reference trace does not register undo nor call `updateChangeCount:` → document not marked edited, changes can be lost. | [#8](https://github.com/banyanshade-software/BikePlanner/issues/8) |
| 4 | M | `MapController.m:750` | Route requests are not cancelled or sequenced: a slow earlier response can overwrite the result of a later one. | [#9](https://github.com/banyanshade-software/BikePlanner/issues/9) |
| 5 | M ✅ | `MapController.m:756` | Routing errors and empty results are only logged; the user gets no feedback. | [#9](https://github.com/banyanshade-software/BikePlanner/issues/9) |
| 6 | M ✅ fixed | `BikePlan.m`, `MapController.m` | `gpxData` (raw BRouter GPX used by the export) was not persisted: after reopening a document, export was disabled until the route was recomputed. The GPX is now saved in the plan (`routeGPX`), part of the undoable route state; documents saved before get a GPX generated from `routePoints` (`exportableGPX`; `testRouteGPXArchivedAndInRouteState`, `testReopenOldDocumentCanExport`). | [#10](https://github.com/banyanshade-software/BikePlanner/issues/10) |
| 7 | M ✅ | `BikePlan.m:325` | After an Overpass error (or HTTP ≥ 300), the retry is scheduled with `performSelector:afterDelay:` from the NSURLSession completion queue, which has no run loop: **the retry never happens** and POIs stay missing until the next route change (`POIFetchTests.testRetryAfterHTTPError`). Query size also grows with route length (one clause per 10 points × 2) — long routes may hit Overpass limits. | [#12](https://github.com/banyanshade-software/BikePlanner/issues/12) |
| 8 | M ✅ fixed | `MapController.m` `exportGpxDataWithPOI:` | GPX export built XML with string formatting, without XML escaping; custom POIs had a nil title (`<name>(null)</name>`). Now escaped (`xmlEscaped`), custom POIs named after their type. Still: custom POIs `gpxSymbol` is “...”. | [#11](https://github.com/banyanshade-software/BikePlanner/issues/11) |
| 9 | M ✅ fixed | `BRouterClient.m` | BRF overrides were joined with `&` and escaped with the deprecated `stringByAddingPercentEscapesUsingEncoding:` (no `&` escaping) inside an `extraParams=` parameter. Now `+[BRouterClient routeURLForServer:…]` builds one percent-encoded `profile:<name>` query item per override (`BRouterClientTests`). | [#15](https://github.com/banyanshade-software/BikePlanner/issues/15) |
| 10 | M ✅ fixed | `Document.m` | *Revert to Saved* replaced `plan` but the map was not refreshed and `poiAvailableCallback` was not re-installed on the new plan. Now `revertToContentsOfURL:ofType:error:` calls `-[MapController planReplaced]` (`testRevertToSavedRefreshesMap`). Still open: a route request in flight during the revert writes its result into the reverted plan when it completes. | [#16](https://github.com/banyanshade-software/BikePlanner/issues/16) |
| 11 | L ✅ fixed | `ElevationProfileView.m` | Division by zero when the route was flat (`maxElev == minElev`): did not crash but drew nothing meaningful. Now the vertical range is at least 100 m (`elevationRangeForMin:max:low:high:`, #32). Axes invisible in dark mode: fixed (`labelColor`). | [#17](https://github.com/banyanshade-software/BikePlanner/issues/17) |
| 12 | L ✅ fixed | `MapController.m` | `excludeControlChanged:` read a POI pointer from `sender.tag`, never set, and did nothing. Include/Exclude now excludes the POI from the export (`BikePlan.excludedPOIKeys`, `POILocation.poiKey`), undoable (`testExcludePOIFromCallout`, `testExcludedPOIsAreNotExported`). | [#5](https://github.com/banyanshade-software/BikePlanner/issues/5) |
| 13 | L ✅ fixed | `MapController.m` | `clearAction:` was unused and would have set `scrubberMarker = nil`: removed. | [#18](https://github.com/banyanshade-software/BikePlanner/issues/18) |
| 14 | L ✅ fixed | `GPXParser.m` | Imported GPX mixed `wpt`, `rtept` and `trkpt` into one point list. Now the trace is the track (else the route, else the waypoints); `wpt` are available apart (`waypoints`). | [#18](https://github.com/banyanshade-software/BikePlanner/issues/18) |
| 15 | L | `BikePlan.m` | `poiUpdateOnProgress` is written from a background thread and read on main. | [#12](https://github.com/banyanshade-software/BikePlanner/issues/12) |
| 16 | M ✅ fixed | `MapController.m` | `distanceAtCoordinate:segstart:` returned the distance on the **first** segment on which the point projects (0 ≤ t ≤ 1), not on the **nearest** segment → in View mode, clicking on the route could put the elevation cursor at a wrong place when the route turns or comes back. Now reuses the nearest-segment projection of `projectedDistanceAlongPolyline:forCoordinate:segment:`. | [#14](https://github.com/banyanshade-software/BikePlanner/issues/14) |
| 17 | L ✅ fixed | `BikePlan.m` / `POILocation.m` | Overpass is asked for `amenity=grave_yard` nodes, but `poiTypeForAmenity:` does not map `grave_yard` → those POIs get type unknown (no icon, no title). | [#13](https://github.com/banyanshade-software/BikePlanner/issues/13) |
| 18 | M ✅ fixed | `MapController.m` `distanceAtCoordinate:segstart:` | Street View heading sometimes wrong shortly after a 90° turn (View-mode click on the route). Cause: #14 (a point just after a corner was located on the incoming segment, so the heading was the incoming one). Fixed with #14, tested (`testBearingJustAfterTurn`), confirmed manually by the owner. | [#21](https://github.com/banyanshade-software/BikePlanner/issues/21) |
| 19 | M ✅ fixed | `MapController.m` `importGPXTraceForDisplay:` | A reference trace (Import GPX as display) could not be removed: it is saved with the document and only undo (right after import) or importing another trace got rid of it. Now *File ▸ Remove Displayed GPX Trace* (`testRemoveReferenceTrace`). | [#24](https://github.com/banyanshade-software/BikePlanner/issues/24) |
| 20 | M ✅ fixed | `GPXParser.m`, `MapController.m` `exportGpxDataWithPOI:` | A GPX exported with POIs was unusable as a reference trace: the POIs are written as `<wpt>` and the parser merged them into the trace (item 14); names were not XML-escaped (item 8). `testExportWithPOIsCanBeImportedAsTrace`. | [#28](https://github.com/banyanshade-software/BikePlanner/issues/28) |
| 21 | M ✅ fixed | `PlannerWindowController.m`, `BRouterClient.m` | BRouter parameter overrides (Params tab) had no effect: brouter.de ignores `extraParams=`, so a single override was lost (with several, all but the first applied); unchecking every override did not go back to the defaults. Fixed with #15; `testBRFOverridesRecomputeRoute`. | [#35](https://github.com/banyanshade-software/BikePlanner/issues/35) |
| 22 | M ✅ fixed | `BRouterClient.m`, `BRFProfileEditor.m` | Boolean overrides were sent as `profile:<name>=true/false`, which brouter.de rejects with HTTP 500 (silent, see #9). Now sent as `1`/`0` (`testBooleanOverridesSentAsNumbers`); the Params tab edits them with switches. | [#38](https://github.com/banyanshade-software/BikePlanner/issues/38) |
| 23 | M ✅ fixed | `BRFProfileEditor.m` | Params tab: typing the decimal separator cleared it ("0," → "0"): the value of the number field was read with `-stringValue` on each keystroke, which validates the partial text with the field's `NSNumberFormatter` and writes it back. The text being edited is now read from the field editor (`testTypeDecimalNumber`). | [#45](https://github.com/banyanshade-software/BikePlanner/issues/45) |
| 24 | L ✅ fixed | `Document.xib` | The side panel (Info / Params tabs) shrank when the Params tab was selected: both panes of the map / panel split view had holding priority 250, the same as the default hugging of the Params tab content (stack views, labels). The panel now has holding priority 260: it keeps its width, the map takes the extra space when the window is resized (`testSidePanelWidthStableAcrossTabs`). The panel is now Info (always visible) above a tab view *Street View* / *Params* (`testInfoAlwaysVisibleAboveStreetViewAndParamsTabs`). | [#43](https://github.com/banyanshade-software/BikePlanner/issues/43) |
| 25 | M ✅ fixed | `Document.xib` (search field) | The location search ran on each keystroke (`sendsSearchStringImmediately`) and again whenever the search field lost the focus (`sendsActionOnEndEditing`), e.g. when typing a value in the Params tab: the map jumped back to the searched place. The search now runs only on Return (`sendsWholeSearchString`; `testLocationSearchOnlyOnReturn`). | [#41](https://github.com/banyanshade-software/BikePlanner/issues/41) |
| 26 | L ✅ fixed | `BRFProfileEditor.m` | Profile parameters were missing in the Params tab for profiles other than trekking (e.g. `iswet` of `mtb.brf`): the `assign name value` syntax (no `=`) was not recognized, and in profiles mixing brouter-web annotations and commented parameters only the annotated ones were kept. Both syntaxes are now parsed and commented parameters are kept, their comment as description (`testParseMixedProfile`). | [#52](https://github.com/banyanshade-software/BikePlanner/issues/52) |

### Design / maintainability
- **`MapController` is a god object**: map setup, UI controls built in code, hit testing, geometry, routing,
  POIs, export, undo. Candidates for extraction: geometry utilities (projection, distance along route, bearing —
  pure functions, easily unit-testable), GPX writer, route service, map controls.
- **Model mixes persistence and networking** (`BikePlan` fetches POIs). A separate POI service would be cleaner.
- Waypoint annotations are kept in sync manually with the model array (`waypointsRouteAnnotations`, `recalcAnnotIndexesFrom:`).
- Magic numbers: click modes 0–3, map types 0–4, polyline tags 0–2, pixel tolerances.
- Profile name `trekking` hard-coded in two places; endpoints hard-coded in four files.
- Dead code: `#if 0` blocks in `SafeOSMTileOverlay`, `SafeTileRenderer`, `MapController`; empty `BikeMapView`.
- No automated test of the real external services (only the stub); the Street View page, tile loading,
  `MKLocalSearch` and the user location are not tested.
- `BRouterClient` creates a new `NSURLSession` per request and never invalidates it (leak).
- No User-Agent on tile requests (OSM tile usage policy requires an identifying one).

## 10. Directions for the reliability work (proposal)

1. ~~Add a `CLAUDE.md` and a command-line build~~ (done).
2. ~~Unit tests on pure code~~ (done: `GPXParser`, `BikePlan`, `POILocation`, `Document`, geometry, GPX export, elevation profile).
2b. ~~Test coverage of all classes, offline test infrastructure, UI tests~~ (done: 86 % line coverage, 132 tests).
3. Fix the high-severity items of §9 one by one, each with a test where possible.
4. Then refactor `MapController` incrementally, behind those tests.

Each step to be validated with the owner before starting.
