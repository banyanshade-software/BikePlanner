# BikePlanner

A native macOS app to plan bicycle routes: place waypoints on a map, get a cycling route from
[BRouter](https://brouter.de), check its elevation profile, road types and points of interest along the way,
preview the road in Google Street View, and export a GPX file for a bike GPS (Garmin, etc.).

BikePlanner is a **personal project**, not distributed yet (see
[distribution constraints](doc/03-distribution-constraints.md)).

## Features

- **Route building** on the map: start, destination and intermediate waypoints (Edit / Add / POI / View click
  modes, with keyboard shortcuts), reverse route, clear route; undo/redo of every change.
- **Routing** by a BRouter server (`brouter.de` by default), with the profile parameters editable in the
  *Params* tab and saved in the document.
- **Base maps**: OpenStreetMap, OpenCycleMap (Thunderforest), Apple standard / hybrid / satellite; place search.
- **Route info**: length, ascent, estimated riding time and speed, distance by road type and surface.
- **Elevation profile** with slope coloring and a cursor linked to the map and to Street View.
- **Points of interest** along the route from OpenStreetMap (Overpass): drinking water, toilets, bicycle repair
  stations, cemeteries; plus typed custom POIs.
- **GPX**: import a trace as a reference or as an editable route; export the route, optionally with the POIs as
  Garmin-compatible waypoints (see [README.POI.GARMIN.txt](README.POI.GARMIN.txt)).
- Documents (`.bikeplan`) with autosave and versions; Preferences (default position, initial map radius…).

## Requirements

- macOS 12.7 or later, an Internet connection (routing, maps, POIs, Street View).
- To build: Xcode, and a [Thunderforest](https://www.thunderforest.com) API key for the OpenCycleMap base map
  (the free *Hobby Project* tier is enough).

## Build

```sh
cp BikePlanner/Secret.h.example BikePlanner/Secret.h   # git-ignored; put your Thunderforest key in it
open BikePlanner.xcodeproj                             # then Run (⌘R) / Test (⌘U)
```

From the command line, without a signing identity (ad hoc signing):

```sh
xcodebuild -project BikePlanner.xcodeproj -scheme BikePlanner -destination platform=macOS,arch=arm64 \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
```

Tests (unit and UI) run offline against a local stub of the external services: see [CLAUDE.md](CLAUDE.md) for the
commands and conventions. `scripts/make_dmg.sh` packages the app as a DMG (not notarized).

## Documentation

- [High-level specification](doc/01-high-level-spec.md) — what the app does, decisions, open questions
- [Architecture](doc/02-architecture.md) — how it is built, key flows, known bugs and technical debt
- [Distribution constraints](doc/03-distribution-constraints.md) — third-party services, licenses, what is missing
  before sharing the app

Work items are tracked as [GitHub issues](https://github.com/banyanshade-software/BikePlanner/issues).

## Credits

Map data © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors (ODbL). Routing by
[BRouter](https://github.com/abrensch/brouter). Cycle maps © [Thunderforest](https://www.thunderforest.com).
POI icons from [Maki](https://github.com/mapbox/maki). About window:
[DCOAboutWindow](https://github.com/DangerCove/DCOAboutWindow) (© Danger Cove).
