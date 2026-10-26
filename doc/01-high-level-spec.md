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
|                                            | Tabs: [Info] [Params]          |
|                MAP                         |  Info:                         |
|   (base map, route, waypoints, POIs,       |   - route length (km)          |
|    reference GPX trace, scrubber marker)   |   - cumulative elevation (m)   |
|                                            |   - [x] Fetch POI  [x] View POI|
|  overlay controls (bottom-left):           |   - Street View (web view)     |
|   [zoom-][zoom+] [my location]             |  Params:                       |
|   [Edit|Add interm.|Add POI|View] + help   |   - BRouter profile parameters |
|   [OSM|OSM+cycle|Apple|Sat+Rd|Sat]         |                                |
+--------------------------------------------+--------------------------------+
|                     ELEVATION PROFILE                                       |
+-----------------------------------------------------------------------------+
```

All panes are separated by resizable split views.

## 6. Functional requirements

### F1 — Base maps
- F1.1 The user can choose among five map types: **OSM** (default), **OSM+cycle** (Thunderforest),
  **Apple**, **Sat+Rd** (hybrid), **Sat**.
- F1.2 Zoom in / zoom out buttons halve / double the visible span.
- F1.3 “My location” centers the map on the user's position (asks for location permission the first time).
- F1.4 The search field (toolbar) performs an Apple place search near the current region, zooms on the
  first result and drops a pin there.

### F2 — Click modes
The map has four click modes, selectable with the segmented control or the *Edit* menu:

| Mode | Click on the map | Click near the route |
|---|---|---|
| **Edit** (0, default) | Appends a waypoint (first = start, then destinations) | (≤16 px) inserts an intermediate waypoint |
| **Add interm.** (1) | — | (≤50 px) inserts an intermediate waypoint |
| **Add POI** (2) | — | (≤50 px) adds a custom “warning” POI on the route |
| **View** (3) | — | (≤40 px) moves the scrubber there, centers the map, updates Street View and the elevation profile cursor |

In every mode, a click within ~30–36 px of a POI selects that POI and shows its callout instead.
A help text next to the control explains the current mode.

### F3 — Waypoints and route
- F3.1 Waypoints are shown as pins: start (gray, labeled “Start”), intermediate (yellow, numbered), last (white).
- F3.2 Waypoints can be **dragged**; dropping one recomputes the route.
- F3.3 Right-click on a waypoint → “Remove Waypoint”.
- F3.4 An intermediate waypoint inserted by clicking on the route is placed at the correct position in the
  waypoint sequence (based on its distance along the current route).
- F3.5 As soon as there are ≥2 waypoints, any change triggers a new BRouter request; the route is drawn in
  semi-transparent blue.
- F3.6 The *Info* tab shows route length (km, rounded) and cumulative ascent (m, BRouter “filtered ascend”).
- F3.7 All waypoint operations (add, insert, move, remove) are **undoable/redoable** (Edit ▸ Undo/Redo),
  as well as adding a custom POI and importing a reference trace.

### F4 — Routing parameters
- F4.1 Routing uses the BRouter `trekking` profile.
- F4.2 The *Params* tab downloads the `trekking.brf` profile and lists every `assign <name> = <value>`
  parameter with an “Override” checkbox and an editable value.
- F4.3 “Done/Save” recomputes the route with the overridden parameters (sent as `profile:<name>=<value>`).
- F4.4 *(partial)* Overrides are not saved in the document and are lost when the window closes.
- F4.5 *(planned, mandatory)* The user chooses the BRouter profile (e.g. `trekking`, `fastbike`, `safety`, …);
  the chosen profile and its overrides are saved in the document.
- F4.6 *(planned)* The BRouter server is configurable; the target is a **local BRouter server**
  (e.g. `http://127.0.0.1:17777`), `brouter.de` remaining a fallback.

### F5 — Elevation profile
- F5.1 Shows altitude vs. distance for the computed route; segment color depends on slope:
  red > +5 %, blue < −5 %, green otherwise.
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
- F7.2 Requests are throttled (≥ ~2.8 s apart) and retried on error.
- F7.3 “View POI” toggles display of fetched POIs. Custom POIs are always shown.
- F7.4 Each POI type has its own icon and color; the POI under the mouse is highlighted.
- F7.5 Clicking a POI shows a callout with its raw OSM tags and an Include/Exclude control
  *(partial: the control has no effect yet)*.
- F7.6 In *Add POI* mode the user adds a custom “warning” POI on the route.
- F7.7 *(planned)* Custom POIs have a **type** chosen by the user (water, food, danger, viewpoint, …, mapped to
  Garmin types for export), and can be edited and removed.

### F8 — Reference GPX trace
- F8.1 *File ▸ Import GPX as display* (or toolbar “Import trace”) loads a GPX file and draws it in
  orange under the route, for reference only (it is not used for routing).

### F9 — Documents
- F9.1 A plan is a document of type `.bikeplan` (UTI `fr.free.daniel.braun.bikeplan`), saved with
  macOS autosave-in-place, versions, Revert, Open Recent.
- F9.2 A document stores: waypoints, computed route points (with altitude), the reference GPX trace,
  route length & ascent, fetched POIs, custom POIs.
- F9.3 On open, the map zooms to the route (or to the user's location if there is no route).

### F10 — Export
- F10.1 *File ▸ Export to GPX* (or toolbar) saves the route as GPX. The track name is the file name.
- F10.2 An option in the save panel adds custom and fetched POIs as GPX `<wpt>` elements, with a
  Garmin-compatible `<type>` (WATER, TOILET, SERVICE, GENERIC, DANGER — see `README.POI.GARMIN.txt`).
- F10.3 *(planned)* *Export to FIT* (Garmin course) — menu item exists, not implemented.
- F10.4 Export is only possible once a route has been computed in the current session.

### F11 — Misc
- F11.1 Custom About window (BSSUI / DCOAboutWindow).

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
- **Custom POIs**: will have types (F7.7).
- **FIT export**: was intended for Garmin; not implemented (F10.3).
- **Distribution**: personal use for now. Constraints for a wider distribution are listed in
  [03-distribution-constraints.md](03-distribution-constraints.md).

Still open:
1. **Include/Exclude POI**: what should it do — exclude the POI from GPX export, hide it, or make the route avoid/go through it?
2. **Multi-day tours**: is splitting a route into stages a goal?
3. **Custom POI types**: which list exactly (subset of Garmin types in `README.POI.GARMIN.txt`?), and do they need a name/description?
