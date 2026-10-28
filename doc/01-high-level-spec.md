# BikePlanner — High-Level Specification

Status: **describes the application as it exists today** (branch `dev`, October 2026), reconstructed from the source code.
Items marked *(planned)* or *(partial)* are visible in the UI or code but not, or not fully, implemented.
Open questions are listed at the end; they need an answer from the project owner.

---

## 1. Purpose

BikePlanner is a native macOS application for **planning bicycle itineraries**.
The user places waypoints on a map, the app computes a cycling route between them with the
[BRouter](https://brouter.de) routing engine, shows its elevation profile, lists useful points of
interest (water, toilets, repair stations, cemeteries) along the route, lets the user preview the
road with Google Street View, and exports the result as a GPX file for a bike GPS (Garmin, etc.).

Target user: a single cyclist preparing day rides or multi-day tours on a Mac, before uploading
the track to a GPS device.

## 2. Scope

### In scope
- Interactive route building on a map (start, destination, intermediate waypoints).
- Route computation by an online BRouter server.
- Display of several base maps (OpenStreetMap, OpenCycleMap, Apple Maps, satellite).
- Elevation profile with slope coloring, linked to the map.
- Street-level preview of any point of the route.
- Points of interest near the route (automatically fetched + user-added).
- Overlay of an existing GPX trace for reference.
- Save/restore of a plan as a document; undo/redo of waypoint edits.
- GPX export, optionally including POIs as waypoints.

### Out of scope (today)
- Turn-by-turn navigation, live tracking.
- iOS / iPadOS versions.
- Offline routing or offline maps.
- Multi-user / cloud sync.

## 3. Platform and environment

| Item | Value |
|---|---|
| Platform | macOS, deployment target 12.7 |
| Language / UI | Objective-C, AppKit (Cocoa), XIB-based UI |
| App type | Document-based (`NSDocument`), sandboxed |
| Network | Required (routing, tiles, POIs, Street View) |
| Location | Optional (“center on my position” button) |
| Bundle id | `fr.free.daniel.braun.BikePlanner` |

## 4. External services

| Service | Use | Notes |
|---|---|---|
| **BRouter** (`https://brouter.de/brouter`) | Route computation (GPX output), profile download (`/brouter/profiles2/<name>.brf`) | Profile currently fixed to `trekking`. |
| **OpenStreetMap tiles** (`tile.openstreetmap.org`) | Default base map | Subject to the OSM tile usage policy. |
| **Thunderforest OpenCycleMap** (`tile.thunderforest.com/cycle`) | “OSM+cycle” base map | Needs an API key, provided at build time in `BikePlanner/Secret.h` (not committed, see `Secret.h.example`). |
| **Apple MapKit** | Apple standard / hybrid / satellite maps, place search, user location | |
| **Overpass API** (`overpass-api.de`) | Fetch POIs along the route | |
| **Google Maps Street View** (web page in a `WKWebView`) | Street-level preview | Uses the public `google.com/maps/@?api=1&map_action=pano` URL, no API key. |

## 5. Main window

One window per document. Layout:

```
+-----------------------------------------------------------------------------+
| Toolbar: [Print] [Import trace]          [Export GPX]        [Search field] |
+--------------------------------------------+--------------------------------+
|                                            | Info (always visible):         |
|                MAP                         |   - route length (km)          |
|   (base map, route, waypoints, POIs,       |   - cumulative elevation (m)   |
|    reference GPX trace, scrubber marker)   |   - riding time, avg speed     |
|                                            |   - [x] Fetch POI  [x] View POI|
|                                            |--------------------------------|
|  overlay controls (bottom-left):           | Tabs: [Street View] [Params]   |
|   [zoom-][zoom+] [my location]             |   Street View (web view) or    |
|   [Edit|Add interm.|Add POI|View] + help   |   BRouter profile parameters   |
|   [OSM|OSM+cycle|Apple|Sat+Rd|Sat]         |                                |
+--------------------------------------------+--------------------------------+
|                     ELEVATION PROFILE                                       |
+-----------------------------------------------------------------------------+
```

All panes are separated by resizable split views. The side panel keeps its width when switching tabs or resizing
the window (the map takes the extra space). Info stays visible above the tabs, so that the effect of new
parameters (Params tab) on the length, time and speed of the route is seen (#43).

## 6. Functional requirements

### F1 — Base maps
- F1.1 The user can choose among five map types: **OSM** (default), **OSM+cycle** (Thunderforest),
  **Apple**, **Sat+Rd** (hybrid), **Sat**.
- F1.2 Zoom in / zoom out buttons halve / double the visible span.
- F1.3 “My location” centers the map on the user's position (asks for location permission the first time).
- F1.4 On Return (not while typing, nor when the field loses the focus), the search field (toolbar) performs an
  Apple place search near the current region, zooms on the
  first result and drops a pin there.
- F1.5 A plan without route opens on a region of ~80 km radius (defaults key `BPInitialRadiusKm`) around the
  user location; until the location is known, or if it is refused, around the default position (key
  `BPDefaultPosition`, “lat,lon”; to be set in the Preferences, #27). The first location recenters the map,
  unless the user has moved it or started placing waypoints.

### F2 — Click modes
The map has four click modes, selectable with the segmented control or the *Edit ▸ Mode* menu items
(⌘1 Edit, ⌘2 Add interm., ⌘3 Add POI, ⌘4 View; the current mode is checked). On a non-QWERTY layout macOS
adapts the shortcut to the key carrying the digit (e.g. ⌘& on AZERTY, i.e. ⌘ + the “1” key without Shift):

| Mode | Click on the map | Click near the route |
|---|---|---|
| **Edit** (0, default) | Appends a waypoint (first = start, then destinations) | (≤16 px) inserts an intermediate waypoint |
| **Add interm.** (1) | — | (≤50 px) inserts an intermediate waypoint |
| **Add POI** (2) | — | (≤50 px) adds a custom “warning” POI on the route |
| **View** (3) | — | (≤40 px) moves the scrubber there, centers the map, updates Street View and the elevation profile cursor |

In every mode, a click within ~30–36 px of a POI selects that POI and shows its callout instead.
A help text next to the control explains the current mode. The map type and click mode controls, the help text and
the zoom / location buttons sit on a translucent blurred backdrop, so they stay readable on any map content while the map remains visible.

### F3 — Waypoints and route
- F3.1 Waypoints are shown as pins: start (gray, labeled “Start”), intermediate (yellow, numbered), last (white).
- F3.2 Waypoints can be **dragged**; dropping one recomputes the route.
- F3.3 Right-click on a waypoint → “Remove Waypoint”.
- F3.4 An intermediate waypoint inserted by clicking on the route is placed at the correct position in the
  waypoint sequence (based on its distance along the current route).
- F3.5 As soon as there are ≥2 waypoints, any change triggers a new BRouter request; the route is drawn in
  semi-transparent blue.
- F3.6 The *Info* section shows route length (km, rounded), cumulative ascent (m, BRouter “filtered ascend”), and the
  riding time and average speed estimated by BRouter (`time=` of the GPX header). BRouter computes the time with
  the kinematic model of the profile (`totalMass` 90 kg, `bikerPower` 100 W, `S_C_x` 0.225, `C_r` 0.01, `maxSpeed`
  45 km/h in `trekking`): continuous power, no stops — optimistic for a loaded touring bike (#30). These parameters
  can be overridden per request (`profile:<name>=<value>`, see F4).
- F3.7 All waypoint operations (add, insert, move, remove, reverse) are **undoable/redoable** (Edit ▸ Undo/Redo),
  as well as adding a custom POI and importing a reference trace.
- F3.8 *Edit ▸ Reverse Route* or the toolbar *Reverse* button (enabled with ≥ 2 waypoints) swaps start and end: the waypoint order is reversed
  and the route is **recomputed** by BRouter (one-way streets, climbs differ in the other direction).
- F3.9 *Edit ▸ Clear Route* or the toolbar *Clear* button (enabled with ≥ 1 waypoint) asks for confirmation (sheet), then erases waypoints, route,
  length/ascent, fetched and custom POIs, but **keeps the reference trace**. Undo restores the route as it was
  (no new BRouter request).

### F4 — Routing parameters
- F4.1 Routing uses the BRouter `trekking` profile.
- F4.2 The *Params* tab downloads the `trekking.brf` profile and shows its user parameters: the ones annotated
  `# %<name>% | <description> | boolean|number|[0=…, 1=…]` (the brouter-web format), in the global context, grouped
  by the profile's section comments (all simple `assign <name> = <value>` when the profile has no annotation).
  BRouter output options (turn instructions, `processUnusedTags`) are hidden. Each parameter has a readable label
  (with the unit from the description), its description and default value, and a control: switch (boolean),
  number field, or pop-up menu (list). A parameter is overridden when its value differs from the default: its label
  is in bold, with a reset button; “Reset to Defaults” resets them all.
- F4.3 “Apply” (enabled when the values differ from the last Apply) recomputes the route with the overridden
  parameters, each sent as a top-level `profile:<name>=<value>` query parameter (what BRouter reads; an
  `extraParams=` wrapper is ignored). Booleans are sent as `1`/`0` (brouter.de fails with HTTP 500 on `true`/`false`).
  With no override, the route uses the profile defaults.
- F4.4 The applied parameters are saved in the document (`BikePlan.profileOverrides`) and shown in the
  *Params* tab when it is opened; Apply is undoable (“change routing parameters”) and Revert to Saved restores them.
  Documents saved before have none (= profile defaults).
- F4.4.1 **My defaults**: the “Defaults” pull-down of the *Params* tab offers *Reset to Profile Defaults*,
  *Use My Defaults* and *Save as My Defaults* (user defaults `BPProfileOverrides`, profile name → parameters). A new
  document starts with my defaults. When an opened document's parameters differ from my defaults, a notice offers
  *Use My Defaults* (the values are then sent with Apply).
- F4.5 *(planned, mandatory)* The user chooses the BRouter profile (e.g. `trekking`, `fastbike`, `safety`, …);
  the chosen profile is saved in the document (its overrides already are, F4.4).
- F4.6 *(planned)* The BRouter server is configurable; the target is a **local BRouter server**
  (e.g. `http://127.0.0.1:17777`), `brouter.de` remaining a fallback.

### F5 — Elevation profile
- F5.1 Shows altitude vs. distance for the computed route; segment color depends on slope:
  red > +5 %, blue < −5 %, green otherwise.
- F5.3 Scale: altitude labels (m) with light grid lines on the left, distance labels (km) at the bottom. The
  vertical range is at least 100 m, centered on the route, so small differences do not look steep; it is
  extended to round values.
- F5.2 Clicking or dragging in the profile moves a dashed cursor, moves the scrubber marker on the map,
  centers the map there and updates Street View, looking in the direction of travel.

### F6 — Street View
- F6.1 The Street View pane shows Google Street View at a given coordinate and heading.
- F6.2 It is updated when a destination waypoint is added, when the user clicks on the route in View mode,
  and when the user scrubs the elevation profile.

### F7 — Points of interest
- F7.1 When “Fetch POI” is on, after each route change the app queries Overpass for, within 1.5 km of
  (a sample of) the route points: drinking water, toilets, bicycle repair stations, grave yards (nodes)
  and cemeteries (land use areas).
- F7.2 Requests are throttled (≥ ~2.8 s apart). A retry on error is intended but does not work today (#12).
- F7.3 “View POI” toggles display of fetched POIs. Custom POIs are always shown.
- F7.4 Each POI type has its own icon and color; the POI under the mouse is highlighted.
- F7.5 Clicking a POI shows a callout with its raw OSM tags and an Include/Exclude control. An excluded POI stays
  on the map, greyed, and is **not exported** to GPX (fetched and custom POIs). Exclusions are saved with the
  document (by OSM id + position, since fetched POIs are re-created at each route change) and undoable (#5).
- F7.6 In *Add POI* mode, a click on the route opens a sheet asking the **type** and an optional **name** of the
  custom POI; Cancel adds nothing (#3).
- F7.7 Custom POI types: Danger (default), Water, Food, Toilets, Bike repair, Shelter, Viewpoint, Campsite, Store,
  Information, Other — exported with the Garmin `<type>` DANGER, WATER, FOOD, TOILET, SERVICE, SHELTER, OVERLOOK,
  CAMPSITE, STORE, INFO, GENERIC (see `README.POI.GARMIN.txt`). The exported `<name>` is the POI name, else the type
  name. Right-click on a custom POI: *Edit POI…* (same sheet) and *Remove POI*. Add / edit / remove are undoable and
  mark the document as edited.

### F8 — Reference GPX trace
- F8.1 *File ▸ Import GPX as display* (or toolbar “Import trace”) loads a GPX file and draws it in
  orange under the route, for reference only (it is not used for routing). Importing another trace replaces it.
- F8.2 *File ▸ Remove Displayed GPX Trace* (enabled when a trace is shown) removes it; undoable.
- F8.3 *File ▸ Import GPX as Route…* converts a GPX into an editable plan: a track (`<trk>`) is simplified into
  waypoints (Douglas–Peucker, 50 m tolerance, at most 3 km between two waypoints along the track, first/last points
  kept), route points (`<rte>`) or a file of `<wpt>` only are used as waypoints as is; then the route is requested
  from BRouter. The original GPX becomes the reference trace (F8.1) to compare with the computed route. `<wpt>`
  become custom POIs, except those with a fetched-POI type (WATER, TOILET, SERVICE, GENERIC), fetched again along
  the new route. If the plan is not empty, a confirmation sheet asks before replacing it. One undoable action.

### F9 — Documents
- F9.1 A plan is a document of type `.bikeplan` (UTI `fr.free.daniel.braun.bikeplan`), saved with
  macOS autosave-in-place, versions, Revert, Open Recent.
- F9.2 A document stores: waypoints, computed route points (with altitude), the reference GPX trace,
  route length & ascent, riding time, fetched POIs, custom POIs.
- F9.3 On open, the map zooms to the route (or to the user's location if there is no route).

### F10 — Export
- F10.1 *File ▸ Export to GPX* (or toolbar) saves the route as GPX. The track name is the file name.
- F10.2 An option in the save panel adds custom and fetched POIs as GPX `<wpt>` elements, with a
  Garmin-compatible `<type>` (WATER, TOILET, SERVICE, GENERIC, DANGER — see `README.POI.GARMIN.txt`).
- F10.3 *(planned)* *Export to FIT* (Garmin course) — menu item exists, not implemented.
- F10.4 Export is only possible once a route has been computed in the current session.

### F11 — Misc
- F11.1 Custom About window (BSSUI / DCOAboutWindow). *Visit the BikePlanner Website* opens the GitHub page
  (Info.plist key `BPWebsiteURL`). It shows `Version <MARKETING_VERSION> (Build <commit count>,
  <short hash>[-dirty], <branch>)`, so a running app tells which code it contains.

## 7. Non-functional requirements (targets)

- **Responsiveness**: the UI must never block on network; all requests are asynchronous.
- **Robustness**: network failures must not crash or corrupt the document; the user should be told when
  routing fails *(today errors are only logged)*.
- **Data safety**: every user change must mark the document as edited so it gets saved.
- **Fair use of free services**: respect OSM tile policy, Overpass and brouter.de rate limits; identify the
  app with a proper User-Agent.
- **Secrets**: API keys are never committed.
- **Localization**: UI strings in English; code uses `NSLocalizedString` in places, no translation yet.

## 8. Glossary

| Term | Meaning |
|---|---|
| Waypoint | Point chosen by the user that the route must go through. |
| Route | Sequence of points (lat, lon, altitude) returned by BRouter. |
| Plan | The document content (`BikePlan`): waypoints + route + POIs + reference trace. |
| Profile (BRF) | BRouter routing profile (cost rules), e.g. `trekking`. |
| POI | Point of interest near the route. Fetched (Overpass) or custom (user-added). |
| Scrubber | Marker on the map synchronized with the elevation profile cursor. |
| Reference trace | An imported GPX displayed for comparison only. |

## 9. Decisions and open questions

Decided (October 2026):
- **BRouter profiles**: choosing the profile is a mandatory future feature (F4.5).
- **BRouter server**: must eventually be a local server (F4.6).
- **Custom POIs**: typed, with an optional name (F7.7).
- **FIT export**: was intended for Garmin; not implemented (F10.3).
- **Import GPX as route** (F8.3): fixed simplification (50 m / 3 km), no slider for now; `<rte>` points are used
  directly as waypoints.
- **Distribution**: personal use for now. Constraints for a wider distribution are listed in
  [03-distribution-constraints.md](03-distribution-constraints.md).

Still open:
1. **Include/Exclude POI**: what should it do — exclude the POI from GPX export, hide it, or make the route avoid/go through it?
2. **Multi-day tours**: is splitting a route into stages a goal?
3. **Custom POI types**: which list exactly (subset of Garmin types in `README.POI.GARMIN.txt`?), and do they need a name/description?
