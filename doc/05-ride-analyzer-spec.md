# Ride Analyzer — Specification (draft)

A second macOS app, next to BikePlanner, that fetches the rides actually done and analyses them (#82).
Branch `ride_analyzer`, from `v10`. Each feature below is proposed, then accepted (or not) by the owner.

Status: **draft** — feature list reviewed with the owner on 2026-11-21 (R1–R15); no design yet.

Mockup (2026-11-21): `doc/05-ride-analyzer-mockup.pdf` — library and ride detail (R1–R5, R7, R11–R13, R15), trends
(R6). Sample names and figures are invented.

## Features

### R1 — Fetch rides from Garmin Connect *(accepted 2026-11-21)*
- The Garmin Connect Personal API key is obtained in the embedded browser, in the user's Garmin Connect session
  (the web part of #79, *Settings ▸ Personal API token*), then kept in the Keychain. No key in the app.
- The app lists the user's cycling activities, downloads their FIT files and, on later launches, fetches only the
  new ones.
- The raw FIT files are kept locally.
- **Bulk import** *(added 2026-11-21)*: one command fetches all the new rides since the last fetch (or over a chosen
  period, e.g. the first import of a whole history), with progress, can be cancelled, resumes where it stopped.
- **Also useful in BikePlanner**: *Import Track as Display…* / *Import Track as Route…* (F8.1, F8.3) can import an
  activity directly from Garmin Connect, instead of exporting it as a GPX / TCX / FIT file first.

### R2 — Import rides from local files *(accepted 2026-11-21)*
- FIT, GPX or TCX files, by drag and drop or the File menu (reuses the parsers of BikePlanner: `BPFITDecoder`,
  `GPXParser`). Several files at once: multiple selection in the open panel, several files or a whole folder
  dropped; one progress and one summary for the batch (imported, skipped as duplicates, unreadable).
- Direct import from the bike computer connected by USB (its `Garmin/Activity` folder).
- A ride already fetched from Garmin Connect (R1) is recognized and skipped (no duplicates).

### R3 — Ride library *(accepted 2026-11-21)*
- A list of all the rides: date, name, distance, ascent, duration, average speed.
- Sortable; search by name.
- **Filters** *(precised 2026-11-21)*, combinable and reusable everywhere (library, statistics R6, climbs R7, heatmap
  R10, zones R14): period, **device** (from the FIT file: e.g. the watch used for commuting vs. the Edge), bike,
  distance (> x km), ascent, tags. Filters can be saved with a name.
- Each ride can be renamed, annotated (free notes, tags) and deleted.

### R4 — Ride detail view *(accepted 2026-11-21)*
- The track on the map (same base maps as BikePlanner), colored by speed, slope, heart rate or power (user's choice).
- Elevation profile linked to the map: synchronized cursor, zoom (reuses `ElevationProfileView`, F5).
- Speed / heart rate / cadence / power / temperature curves, depending on what the FIT file contains.
- Summary: moving time, pauses, max speed, averages, calories.

### R5 — Open a ride in BikePlanner *(accepted 2026-11-21, reworded)*
- A command opens BikePlanner with the ride imported (as display, F8.1, or as route, F8.3).
- The comparison of planned and done (track differences on the map, distance, ascent, actual time vs. the time
  estimated by BRouter, per stage; tuning the speed used for the estimates) is a **BikePlanner** feature, not one
  of this app: #88.

### R6 — Statistics and trends *(accepted 2026-11-21)*
- Totals per week, month and year (distance, ascent, time, number of rides), as charts.
- Personal records: longest ride, most ascent, best average speed.
- Trend of the average speed or the heart rate over comparable rides.
- **Charts over time** *(added 2026-11-21)*: any metric against the date (e.g. W/bpm, speed, VAM), on the rides of a
  filter (R3), and restricted to a kind of terrain: flat only, climbs between x and y %, descents… (the ride is
  split in segments by gradient). Also used for the climbs (R7).

### R7 — Climb analysis *(accepted 2026-11-21)*
- Automatic detection of the climbs of a ride: length, ascent, average and max gradient, with time, climbing speed
  (VAM) and heart rate.
- A climb ridden again is compared with the previous passages (best time, trend).
- The analysis is stored with the ride (computed once, recomputed only on request or when the algorithm changes).

### R8 — Road types and surfaces *(accepted 2026-11-21, postponed to a later version of the app)*
- For a ride: distance and time per road type (cycleway, tertiary road, track…) and per surface (asphalt,
  gravel…), with the average speed on each; reuses the *Road types* display of BikePlanner (#66).
- Types from OpenStreetMap: the track is matched to the roads (through BRouter or Overpass).

### R9 — Export and sharing *(accepted 2026-11-21)*
- Export a ride as GPX, optionally cleaned up: pauses removed, start and end trimmed near home.
- Export the library or the statistics as CSV, for a spreadsheet.
- An image of the ride (map, profile, key figures) to share.

### R10 — Map of all rides (heatmap) *(accepted 2026-11-21)*
- All the tracks drawn on one map; the most ridden roads stand out. Filters of R3.
- The map can be zoomed and panned; the default zoom shows all the tracks of the filter.
- Shows the roads never ridden, to take into account when planning a route in BikePlanner.

### R11 — Estimated power *(requested by the owner 2026-11-21)*
- When the ride has no power meter data, the power (W) is computed along the ride from speed, gradient and
  acceleration: gravity, rolling resistance, air drag.
- This needs the equipment, filled in by the user:
  - the bikes (type, weight, riding position → drag area);
  - the tyres (model, width → rolling resistance), which change over time: each ride uses the tyres mounted at its
    date (equipment history);
  - the rider's weight, from Garmin Connect when available (the Personal API gives weight data), otherwise entered.
- Each ride is linked to a bike (default bike, or chosen).
- Estimated values are shown as such (not mixed with measured power).
- Computed only for the rides of a chosen filter (R3): e.g. rides recorded with the Edge, not the imprecise watch
  used for commuting.

### R12 — Weather of the ride *(accepted 2026-11-21)*
- Wind (speed, direction) and temperature from a historical weather service, for the date and place of the ride.
- Shown in the ride detail (R4); used by the estimated power (R11) and to explain a speed (headwind, tailwind).
- Fetched once and stored with the ride.
- The service is to be chosen (free, no key in the app, terms compatible): routed through an environment hook like
  the other endpoints of BikePlanner.

### R13 — Equipment tracking *(accepted 2026-11-21, precised)*
- The bikes and parts (tyres, chain, brake pads…) used by R11: distance per bike and per part.
- A part is **valid on a time range**: mounted on a given bike from a date to a date (open while still mounted).
  A ride uses the parts mounted on its bike at its date.
- The equipment defined in Garmin Connect (gear: bikes…) is taken over (through the Personal API if it gives it,
  otherwise the web session, #79); the tyres are then associated with a bike in the app.
- The rolling resistance coefficient (Crr) of each tyre is shown and can be corrected (default from the model and
  width).
- A wear threshold per part, and a reminder when it is reached.

### R14 — Heart rate and power zones *(accepted 2026-11-21)*
- Time in each zone, for a ride and over a period.
- From the max heart rate and the power threshold (FTP), entered or taken from Garmin Connect.
- With the estimated power (R11) when there is no power meter.

### R15 — Library file *(requested by the owner 2026-11-21)*
- The library (rides, analyses, equipment, settings) is a file chosen by the user: one per person on a shared
  computer. The last one is reopened at launch; another one can be opened or created.
- Each library has its own Garmin Connect account (key in the Keychain, per library).

## Related BikePlanner items
- Import an activity directly from Garmin Connect as display or as route (R1).
- Planned vs. done comparison (R5): a BikePlanner feature, #88.

## Skeleton (2026-11-21)
Decided with the owner: a second app target **`RideAnalyzer`** in `BikePlanner.xcodeproj` (shared sources compiled
in both apps), Objective-C like BikePlanner, **document-based**: a document is a library (R15).
- `RideAnalyzer/`: `main.m` and `RAAppDelegate` (menu built in code, no XIB; the last library reopened at launch),
  `RALibraryDocument` (the library), `RARide` (one ride and its figures), `RALibraryWindowController` (window built
  in code: sidebar, list of rides, detail of the selected ride), `Info.plist` (document type), entitlements (sandbox,
  user-selected files, network client).
- Library file: a package `.ridelib` (UTI `fr.free.daniel.braun.ridelib`): `Library.plist` (the rides, binary
  property list, `version` 1) and `Rides/` (the original files, as imported).
- Shared with BikePlanner: `BPTrackReader`, `GPXParser`, `BPFITDecoder` (R2).
- Works: File ▸ New / Open Library, rename (in the list), delete, undo, sorting; figures: distance, ascent (3 m
  threshold), duration, average speed.
- Tests: `RideAnalyzerTests` (hosted in RideAnalyzer), scheme `RideAnalyzer`; helpers in `RATestSupport`
  (ride files in the three formats, a ZIP writer, `RAStubURLProtocol`: a stub of the Garmin Connect Personal API).

## Imports (2026-11-21, R1, R2, R3 devices)
- **Background imports** (`RALibraryDocument`): the files are read off the main thread, with an `NSProgress` shown
  above the list (text, bar, Cancel). The new rides are added at the end in **one undoable action**; a cancelled
  import keeps what was read; importing again resumes (duplicates skipped). One import at a time.
- **Files and folders** (R2): File ▸ Import Files… (several files, folders with their subfolders), or drag and
  drop on the list. Summary: imported, already in the library, unreadable.
- **Device as a disk** (R2): File ▸ Import from Device… finds `<volume>/Garmin/Activity` on the mounted volumes and
  opens the panel there (the sandbox needs the user's choice). Recent devices that connect with MTP do not show as
  a disk: they go through Garmin Connect.
- **Duplicates**: same file (SHA-256), same Garmin activity, or same ride (start within a minute, distance within
  2 %), in the library or earlier in the same import. A Garmin activity that is the duplicate of a ride imported
  from a file is linked to it (so the next fetches stop there).
- **Garmin Connect** (R1, `RAGarminConnect`, `RAGarminFetchSheet`): File ▸ Fetch from Garmin Connect… asks for the
  Personal API key (pasted for now; kept in the Keychain, one per library, by the library's `libraryID`) and what
  to fetch: the new rides (the listing, newest first, stops at the first activity already in the library) or all
  the rides since a date (bulk import of a history). Outdoor cycling activities only (not indoor or virtual rides,
  which have no track). The FIT file comes out of the ZIP Garmin sends (`RAZipReader`). The token (about 24 h, no
  refresh token) is obtained again when it expires or on a 401. The date of the last complete fetch is saved in
  the library.
- **Devices** (R3): `BPFITDecoder` now reads `file_id` (manufacturer, product, serial number, creation time) and the
  sport of `sport` / `session`; `BPTrackReader` gives the device (FIT `file_id`, TCX `Creator`: Name, UnitId,
  ProductID) and the sport. A ride's `deviceKey` is `p<product>-s<serial>` (the same unit in FIT and TCX). Its label:
  the name given by the user (sidebar, editable, undoable), else the name a TCX file gave for that unit, else
  "Device <product>". The sidebar lists the devices; selecting one filters the list.
- **GPX times**: `GPXParser` now reads the `<time>` of each point (Z, fractional seconds, offset) and tells whether
  every point has one (`hasTimes`, also in `BPTrackReader` for TCX and FIT). A file without times gives a ride with
  no date rather than the import date. BikePlanner benefits too (imported traces keep their times).
- **To check against the real Garmin service** (not reachable from the session that wrote this): the API host
  (`https://personal.connectapi.garmin.com` assumed, override with the user default `RAGarminAPIBaseURL`), the token
  endpoint and the shape of its answer (`RAGarminTokenURL`; the client accepts `access_token` / `accessToken` /
  `token`, `expires_at` / `expires_in`, or a bare JWT), the activity fields (`activityId`, `activityName`,
  `startTimeGMT`, `distance`, `activityType.typeKey`). Also: getting the key through the web session (#79).

## Handoff (2026-11-21): written without Xcode, never compiled
The skeleton and the imports were written in a session without Xcode. First steps on the owner's Mac (Claude Code):
1. `git checkout ride_analyzer && git pull`.
2. Build `RideAnalyzer` (scheme `RideAnalyzer`, ad hoc signing as above) and fix the compile errors and warnings
   (#58: no warning, `analyze` clean). If Xcode rejects the project file, check the targets added by
   `scripts/xcode_add_target.py --type app / --type unit-test` (first use of these types).
3. Run `RideAnalyzerTests` (`RALibraryTests`, `RAImportTests`, `RAGarminConnectTests`), then the BikePlanner unit
   tests: shared sources changed (`GPXParser` reads `<time>`, `BPFITDecoder` reads `file_id` / sport,
   `BPTrackReader` gives `hasTimes`, device and sport; new tests in `GPXParserTests` and `BPTrackReaderTests`) and
   the project file changed: BikePlanner and its Quick Look extension must still build and pass.
   `RAZipReader` / the tests use the Compression library (`compression.h`): if the link fails, add
   `libcompression.tbd` to the RideAnalyzer target.
4. Launch the app (the owner): New Library, Import Files… (FIT / TCX / GPX, a folder), Import from Device…,
   drag and drop, the progress bar and Cancel, rename a ride and a device, delete, undo, save, reopen.
5. Garmin Connect (the owner, with his Personal API key): File ▸ Fetch from Garmin Connect…; check the points
   listed under "To check against the real Garmin service" above and adjust `RAGarminConnect` (and its stub in
   `RAGarminConnectTests`) to the real answers.
6. Also pending on `v10` (and therefore here): the new Garmin toolbar icon (#85, commit edb4c57) to check, then close
   #85.

## Open questions
- Name of the app (the target is `RideAnalyzer` for now).
- Does the Personal API give the Garmin gear (R13)? To check.
- Map, profile and track display shared with BikePlanner (R4): which classes can be reused as they are
  (`ElevationProfileView`, `BikeMapView`…) and which need to be split from `MapController`.
- The historical weather service (R12).
