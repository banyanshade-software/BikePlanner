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
  main.m, AppDelegate.*      App entry, About window
  Document.*                 NSDocument subclass: load/save, menu relays
  PlannerWindowController.*  Window setup, wires MapController / StreetView / BRF editor
  MapController.*            Map interaction, route requests, annotations, export, undo
  BikePlan.*                 Model: waypoints, route, POIs, reference trace; POI fetching
  ExportAccessoryView*       Accessory view of the GPX save panel ("include POI" checkbox)
  Base.lproj/Document.xib    Document window (split views, map, tabs, profile, toolbar)
  Base.lproj/MainMenu.xib    Menus
  Secret.h.example           Template for Secret.h (Thunderforest API key, git-ignored)
  Assets.xcassets            App icon, POI icons (SVG from mapbox/maki)
SupportClasses/              Reusable/support components
  BRouterClient.*            HTTP client for BRouter
  GPXParser.*                NSXMLParser-based GPX reader + BRouter comment parser
  BRFProfileEditor.*         Downloads a .brf profile and builds a parameter-override UI
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
   `StreetViewController.webView`. Bindings: Info tab labels → `plan.brouterInfo.kmlen` / `plan.brouterInfo.mup`;
   “Fetch POI” → `plan.fetchPOI`; “View POI” → `mapController.viewPOI`; Export toolbar item enabled ↔ `mapController.gpxData`.
4. `-[PlannerWindowController windowDidLoad]` asserts the wiring, then calls
   `-[MapController initializeMapview]`, `-[StreetViewController initializeStreetView]`,
   `-[MapController fullRefresh:YES]` and builds the `BRFProfileEditor` into the *Params* tab.
5. `initializeMapview` creates tile overlays, the `BRouterClient`, the overlay controls (buttons and segmented
   controls are created **in code**, added to the map's superview), the click gesture recognizer, the scrubber
   annotation, the mouse tracking area, and sets `plan.poiAvailableCallback`.

Menu actions (*Edit ▸ Mode…*, *Import*, *Export*) go through the responder chain to `Document`, which relays them
to `MapController`.

## 4. Data model

### 4.1 `BikePlan` (NSSecureCoding)

| Property | Type | Persisted key | Meaning |
|---|---|---|---|
| `waypointsLocations` | `NSArray<CLLocation*>` (immutable, replaced on each change) | `waypointsLocations` | User waypoints, ordered |
| `routePoints` | `NSArray<CLLocation*>` | `routePoints` | Route returned by BRouter, with altitude |
| `gpxDisplayed` | `NSArray<CLLocation*>` | `gpxDisplayed` | Reference trace |
| `brouterInfo` | `BrouterInfo` (`kmlen`, `mup`) | `brouterInfo` | Length (km) and ascent (m) |
| `poiloc` | `NSArray<POILocation*>` | `poiloc` | Fetched POIs |
| `customPoiloc` | `NSMutableArray<POILocation*>` | `customPoiloc` | User POIs |
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
`gpxData` (raw GPX of last route, used for export), `extraUrl` (BRouter overrides), click mode, map type,
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
```
MapController.requestRoute
  gpxData = nil
  BRouterClient.routeWithWaypoints:profile:"trekking" extraUrl:
    GET https://brouter.de/brouter?lonlats=lon,lat|lon,lat…&profile=trekking&alternativeidx=0&format=gpx[&extraParams=…]
    (background) GPXParser → points + brouterInfo (parsed from the GPX comment: track-length, filtered ascend, time, energy)
  completion (background) → error: NSLog only
                          → main queue: plan.brouterInfo.{kmlen,mup}, gpxData, plan.routePoints,
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

- Xcode project `BikePlanner.xcodeproj`, scheme `BikePlanner`, targets: app, unit tests, UI tests.
  The project also contains three leftover targets `BikePlanner_org`, `BikePlanner_orgTests`, `BikePlanne_orgrUITests`
  (empty app from an earlier project); they are not in the scheme and should be deleted.
- Unit tests: `BikePlannerTests` (hosted in the app). See `CLAUDE.md` for the command line.
  Known bugs are documented by tests wrapped in `XCTExpectFailure`.
- New source files are added to the project with `scripts/xcode_add_files.py`.
- macOS deployment target 12.7, ARC on.
- **Before building**: copy `BikePlanner/Secret.h.example` to `BikePlanner/Secret.h` and set `THUNDERFOREST_API_KEY`
  (the build fails without `Secret.h`).
- Entitlements: App Sandbox, user-selected files read/write, outgoing network, location.
- Hard-coded endpoints: see high-level spec §4. They are spread over `MapController.m`, `BikePlan.m`,
  `BRFProfileEditor.m`, `StreetViewController.m`.
- Logging: `NSLog` everywhere, quite verbose (e.g. per-segment logs in `bearingAtDistance:`).

## 9. Technical debt, risks and suspected bugs

Findings from reading the code; those marked ✅ are confirmed by a unit test. Severity: **H** high, **M** medium, **L** low.
Each item is tracked as a GitHub issue.

### Correctness
| # | Sev | Where | Finding | Issue |
|---|---|---|---|---|
| 1 | M | `BikePlan.m:215` | `routePoly` tests `!_waypointPoly` instead of `!_routePoly`. Since `waypointPoly` is never used, the route polyline is rebuilt **on every access** and `shouldRequestPOI` is fired each time (every click near the route, every refresh). The throttling in `tryRequestPoi` (≥ 2.8 s between requests, coalescing timer) limits this to one Overpass request every ~3 s while the user interacts, but each one is a redundant full re-fetch. Fixing it naively would break route refresh, because `setRoutePoints:` does not invalidate `_routePoly` (guarded by `BikePlanTests.testRoutePolyFollowsRoutePoints`). | [#6](https://github.com/banyanshade-software/BikePlanner/issues/6) |
| 2 | H ✅ fixed | `POIAnnotation.h:16`, `POICalloutView.h:14` | `info` / `infodic` are `assign` object properties (= `unsafe_unretained` under ARC) → potential dangling pointer / crash. | [#7](https://github.com/banyanshade-software/BikePlanner/issues/7) |
| 3 | H ✅ fixed | `MapController.m:523`, `MapController.m:1640` | Adding a custom POI or importing a reference trace does not register undo nor call `updateChangeCount:` → document not marked edited, changes can be lost. | [#8](https://github.com/banyanshade-software/BikePlanner/issues/8) |
| 4 | M | `MapController.m:750` | Route requests are not cancelled or sequenced: a slow earlier response can overwrite the result of a later one. | [#9](https://github.com/banyanshade-software/BikePlanner/issues/9) |
| 5 | M | `MapController.m:756` | Routing errors and empty results are only logged; the user gets no feedback. | [#9](https://github.com/banyanshade-software/BikePlanner/issues/9) |
| 6 | M | `MapController.m:930` | `gpxData` is not persisted: after reopening a document, export is disabled until the route is recomputed. | [#10](https://github.com/banyanshade-software/BikePlanner/issues/10) |
| 7 | M | `BikePlan.m:325` | Overpass errors are retried every ~2 s forever, without backoff. Query size grows with route length (one clause per 10 points × 2) — long routes may hit Overpass limits. | [#12](https://github.com/banyanshade-software/BikePlanner/issues/12) |
| 8 | M ✅ | `MapController.m:855` | GPX export builds XML with string formatting, without XML escaping; custom POIs have a nil title (`<name>(null)</name>`) and `gpxSymbol` “...”. | [#11](https://github.com/banyanshade-software/BikePlanner/issues/11) |
| 9 | M | `PlannerWindowController.m:49` | BRF overrides are joined with `&` then escaped with the deprecated `stringByAddingPercentEscapesUsingEncoding:` (does not escape `&`): all but the first override become top-level query parameters. To verify against BRouter's expected format. | [#15](https://github.com/banyanshade-software/BikePlanner/issues/15) |
| 10 | M | `Document.m:134` | *Revert to Saved* replaces `plan` but the map is not refreshed and `poiAvailableCallback` is not re-installed on the new plan. | [#16](https://github.com/banyanshade-software/BikePlanner/issues/16) |
| 11 | L | `ElevationProfileView.m:87` | Division by zero when the route is flat (`maxElev == minElev`): does not crash (tested) but draws nothing meaningful; axes drawn in black (invisible in dark mode). | [#17](https://github.com/banyanshade-software/BikePlanner/issues/17) |
| 12 | L | `MapController.m:1375` | `excludeControlChanged:` reads a POI pointer from `sender.tag`, which is never set. | [#5](https://github.com/banyanshade-software/BikePlanner/issues/5) |
| 13 | L | `MapController.m:426` | `clearAction:` is unused and would set `scrubberMarker = nil`. | [#18](https://github.com/banyanshade-software/BikePlanner/issues/18) |
| 14 | L | `GPXParser.m` | Imported GPX mixes `wpt`, `rtept` and `trkpt` into one point list. | [#18](https://github.com/banyanshade-software/BikePlanner/issues/18) |
| 15 | L | `BikePlan.m` | `poiUpdateOnProgress` is written from a background thread and read on main. | [#12](https://github.com/banyanshade-software/BikePlanner/issues/12) |
| 16 | M ✅ | `MapController.m:1454` | `distanceAtCoordinate:segstart:` returns the distance on the **first** segment on which the point projects (0 ≤ t ≤ 1), not on the **nearest** segment → in View mode, clicking on the route can put the elevation cursor at a wrong place when the route turns or comes back. | [#14](https://github.com/banyanshade-software/BikePlanner/issues/14) |
| 17 | L ✅ fixed | `BikePlan.m` / `POILocation.m` | Overpass is asked for `amenity=grave_yard` nodes, but `poiTypeForAmenity:` does not map `grave_yard` → those POIs get type unknown (no icon, no title). | [#13](https://github.com/banyanshade-software/BikePlanner/issues/13) |

### Design / maintainability
- **`MapController` is a god object**: map setup, UI controls built in code, hit testing, geometry, routing,
  POIs, export, undo. Candidates for extraction: geometry utilities (projection, distance along route, bearing —
  pure functions, easily unit-testable), GPX writer, route service, map controls.
- **Model mixes persistence and networking** (`BikePlan` fetches POIs). A separate POI service would be cleaner.
- Waypoint annotations are kept in sync manually with the model array (`waypointsRouteAnnotations`, `recalcAnnotIndexesFrom:`).
- Magic numbers: click modes 0–3, map types 0–4, polyline tags 0–2, pixel tolerances.
- Profile name `trekking` hard-coded in two places; endpoints hard-coded in four files.
- Dead code: `#if 0` blocks in `SafeOSMTileOverlay`, `SafeTileRenderer`, `MapController`; empty `BikeMapView`.
- Unit tests cover the pure parts only (parser, model, geometry, export); no test of networking or UI.
- `BRouterClient` creates a new `NSURLSession` per request and never invalidates it (leak).
- No User-Agent on tile requests (OSM tile usage policy requires an identifying one).

## 10. Directions for the reliability work (proposal)

1. ~~Add a `CLAUDE.md` and a command-line build~~ (done).
2. ~~Unit tests on pure code~~ (done: `GPXParser`, `BikePlan`, `POILocation`, `Document`, geometry, GPX export, elevation profile).
3. Fix the high-severity items of §9 one by one, each with a test where possible.
4. Then refactor `MapController` incrementally, behind those tests.

Each step to be validated with the owner before starting.
