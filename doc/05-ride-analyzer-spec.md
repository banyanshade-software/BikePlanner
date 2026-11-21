# Ride Analyzer — Specification (draft)

A second macOS app, next to BikePlanner, that fetches the rides actually done and analyses them (#82).
Branch `ride_analyzer`, from `v10`. Each feature below is proposed, then accepted (or not) by the owner.

Status: **draft** — feature list reviewed with the owner on 2026-11-21 (R1–R15); no design yet.

Mockup (2026-11-21): `doc/05-ride-analyzer-mockup.pdf` — library and ride detail (R1–R5, R7, R11–R13, R15), trends
(R6). Sample names and figures are invented.

## Features

### R1 — Fetch rides from Garmin Connect *(accepted 2026-11-21)*
- The Garmin Connect Personal API key is obtained in the embedded browser, in the user's Garmin Connect session
  (the web part of #79, *Settings ▸ Personal API token*), then kept in the Keychain (or, if the user chooses, in
  the library file, R15). No key in the app.
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
- Each library has its own Garmin Connect account (key in the Keychain, per library: two people sharing one Mac
  account each have their own library, so their own key). Not in the user defaults: they are per account, and a
  plain file.
- Option (2026-11-21): the key kept in the library file (checkbox of the fetch sheet), to use the library on
  another Mac. Obfuscated (XOR with a pad derived from the `libraryID`), not encrypted: anyone with the file has
  the key; the sheet says so.
- Copies: a copy of the library must not share the key of the original. The app records, per user account, where
  each library was last opened or saved (`RALibraryLocations`, identifier → path). A library opened from another
  place asks *Moved* / *Copy for Someone Else* / *Copy for Me*; one opened while another open library has the same
  identifier asks the last two. A copy gets a new `libraryID`; for someone else, without the key or the last fetch
  date; for me, the key is copied. Save As and Duplicate make a copy for the same person.

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
  Personal API key (pasted for now; kept in the Keychain, one per library, by the library's `libraryID`, or in the
  library file, R15) and what
  to fetch: the new rides (the listing, newest first, stops at the first activity already in the library) or all
  the rides since a date (bulk import of a history). Outdoor cycling activities only (not indoor or virtual rides,
  which have no track). The FIT file comes out of the ZIP Garmin sends (`RAZipReader`). The token (about 24 h, no
  refresh token) is obtained again when it expires or on a 401. The date of the last complete fetch is saved in
  the library.
- **Devices** (R3): `BPFITDecoder` now reads `file_id` (manufacturer, product, serial number, creation time) and the
  sport of `sport` / `session`; `BPTrackReader` gives the device (FIT `file_id`, TCX `Creator`: Name, UnitId,
  ProductID) and the sport. A ride's `deviceKey` is `p<product>-s<serial>` (the same unit in FIT and TCX). Its label:
  the name given by the user (sidebar, editable, undoable), else the name a TCX file gave for that unit, else the
  model of its Garmin product number (`+[RARide nameOfGarminProduct:]`, a table of the Edge computers and some
  watches from the FIT SDK `garmin_product` type — to check against the SDK's Profile, not verified when written;
  FIT files are named at import, older rides when shown), else "Device <product>". The sidebar lists the devices;
  selecting one filters the list.
- **GPX times**: `GPXParser` now reads the `<time>` of each point (Z, fractional seconds, offset) and tells whether
  every point has one (`hasTimes`, also in `BPTrackReader` for TCX and FIT). A file without times gives a ride with
  no date rather than the import date. BikePlanner benefits too (imported traces keep their times).
- **First try with the owner's key (2026-11-21): HTTP 406** (Not Acceptable), most likely on the token request,
  which accepted JSON only. Changes: the token request accepts any type (`application/json, text/plain, */*`; the
  answer is read as JSON or as a bare token) and sends an empty body with `Content-Length: 0`; a transient answer
  (408, 429, 502–504) gets one retry after `Retry-After` or 2 s; the error says which request failed (token, list,
  download; `RAGarminStepKey`) and shows the start of the answer; the log has a line
  "RideAnalyzer: Garmin Connect <step>: HTTP <status>" (never the key or the token).
- **To check against the real Garmin service** (not reachable from the session that wrote this): the API host
  (`https://personal.connectapi.garmin.com` assumed, override with the user default `RAGarminAPIBaseURL`), the token
  endpoint and the shape of its answer (`RAGarminTokenURL`; the client accepts `access_token` / `accessToken` /
  `token`, `expires_at` / `expires_in`, or a bare JWT), the activity fields (`activityId`, `activityName`,
  `startTimeGMT`, `distance`, `activityType.typeKey`). Also: getting the key through the web session (#79).

## Search, filters, ride detail (2026-11-21, R3, R4)
- **Search** (R3): the search field of the sidebar (Edit ▸ Find…, ⌘F) looks for every word in the name, the notes
  and the tags, case and accents ignored.
- **Filters** (R3, `RAFilter`): period (days), devices, distance (min / max), minimum ascent, tags (any of them);
  combinable, edited in a sheet (Edit ▸ Filter…, ⌥⌘F, `RAFilterSheet`), summarized under the search field, cleared
  with Clear. **Saved filters**: Save… names the current filter (search text included); the sidebar lists them
  (names editable in place, Delete Filter in the contextual menu), all undoable and saved in the library. Selecting
  a device in the sidebar filters on it. The footer gives the totals of the rides shown ("of N" when filtered).
- **Notes and tags** (R3): edited in the detail (a text field, a token field with completion), undoable; tags are
  trimmed, without "#", without duplicates.
- **Ride detail** (R4, `RARideDetailController`): the track is read from the original file in the background
  (`RARideAnalysis`: distance and time from the start, speed — recorded or from distance / time —, slope over about
  100 m, heart rate, cadence, power, temperature; moving time — faster than 3 km/h —, pauses, averages and maxima,
  calories). Shown: the summary; the map (MapKit) with the track colored by speed, slope, heart rate or power and
  its legend (`RATrackColoring`: speed < 18 / 18–24 / 24–30 / > 30 km/h; slope < −4 / −4…−1 / flat / 1–4 / 4–8 /
  > 8 %; heart rate by fractions of the ride's max, power by fractions of its average); the elevation profile
  (`ElevationProfileView`, shared with BikePlanner: zoom, cursor); the curves (`RAChartView`) of the channels the file
  has. One cursor: a click in the profile or a curve moves it on the map and in every curve; zooming the profile
  zooms the curves. The figures are measured only: estimated power comes with R11.
- **FIT / TCX metrics**: `BPFITDecoder` reads the record fields heart_rate, cadence, speed / enhanced_speed, power,
  temperature and the session total_calories; `BPTrackReader` gives them per point (`metrics`, also from TCX:
  HeartRateBpm, Cadence, ActivityExtension Speed / Watts; Lap Calories). GPX: none yet (Garmin's TrackPointExtension
  could be read later).
- **Toolbar** (customizable, saved): sidebar, Import, Device (Import from Device…), Garmin Connect, Trends, Delete,
  Filter; enabled as the menu items.
- **Filter in the sidebar** (owner's request, 2026-11-21; first just above the list, then moved to the sidebar,
  which only listed the saved filters and devices): the search field; pop-up menus for the most used criteria —
  period (any date, last 30 days, last 12 months, this year), device, tag — each showing "Custom…" / "Several…"
  when the filter holds something they do not offer; the **distance** as a slider with two ends (`RARangeSlider`,
  1 km steps, from 0 to the longest ride rounded up to 10 km, at least 50; an end means no limit; the label shows
  the range while dragging, the list follows when the knob is released; arrow keys too); More…
  opens the sheet with every criterion; Clear, Save…; the summary of the filter. Under it, the saved filters and
  the devices (one click applies one; no "All Rides" row: Clear).
- **Tabs beside the list**: *Ride* (the detail) and *Trends* (R6).
- Not yet: the map's base layers of BikePlanner (OSM, Thunderforest: the Apple map for now), a click on the map to
  move the cursor, "Open in BikePlanner" (R5).

## Progression (2026-11-21, R6)
- **Stats of a ride** (`RARideStats`), computed from its track at import and kept with the ride in the library
  (`stats`, versioned): moving time, max speed, heart rate, power, calories, and per terrain — the slope of each
  moving interval: descents (< −1 %), flat (−1 to 1 %), climbs of 1–4 %, 4–8 %, over 8 % — the moving time,
  distance, ascent, heart rate × time and power × time. The rides imported before (or with an older version) get
  theirs in the background when the Trends tab shows (`computeMissingStatsWithCompletion:`). The measures of a
  terrain are therefore those of the parts of the rides on that terrain, not of the whole rides.
- **Trends tab** (beside the list; Window ▸ Trends, ⇧⌘T, toolbar "Trends" switch to it and back;
  `RATrendsViewController`; first a window of its own, made a tab at the owner's request 2026-11-21):
  - rides: the selected rides when two or more are selected, else the rides of the list (the filter, R3);
  - **progression**: a measure — average speed, heart rate, power (measured), W/bpm, speed per heart rate
    (km/h per 100 bpm, without a power meter), climbing speed (VAM) — on a terrain, per ride, week or month
    (a period's value from the sums of its rides), with a trend line (least squares); a ride needs at least
    2 min on the terrain; a click on a point names the ride or the period;
  - **totals** per week, month or year (distance, ascent, moving time, number of rides), empty periods included;
  - **records**: longest ride, most ascent, best average speed over 50 km, longest moving time, highest power.
  - `RATrends` (computations), `RATimeChartView` (points with trend line, or bars).
- Not yet: the estimated power (R11), the climbs (R7, to compare the passages on the same climb), selecting a ride
  of the chart in the library window.

## Map of all rides (2026-11-21, R10)
- **Map tab** beside the list (Window ▸ Map of the Rides, ⇧⌘M, toolbar "Map"; `RARidesMapViewController`): the
  tracks of the selected rides (two or more) or of the list, on a muted Apple map; zoomed on all of them when the
  rides change (*Show All* goes back to it); legend, status (rides, those without track, most rides on a road).
- **Most ridden roads** (`RAHeatmap`): the map is divided in 40 m cells; a cell counts the rides that cross it (the
  tracks are densified every half cell so that no crossed cell is missed); each piece of track gets the level of
  its cell — 1 ride, 2–3, 4–9, 10+ — drawn wider and warmer (blue, yellow, orange, red), the most ridden on top.
  Computed off the main thread.
- **Tracks**: kept in the stats of each ride (`RARideStats.track`, Douglas–Peucker to 8 m, float32 pairs; stats
  version 2), so the files are not read again; the stats of older rides are computed again in the background when
  the Map or Trends tab shows (one computation at a time, `computeMissingStatsWithCompletion:`).
- **Known bug #89**: the tab shows nothing until the window is resized, and drawing is slow; the computation and the
  drawing must be asynchronous.
- Not yet: the roads **never ridden** (needs the road network around: Overpass, as BikePlanner's POIs, or the
  BRouter segments; to be designed), a click on a track to select its ride, BikePlanner's base maps.

## Equipment (2026-11-21, R13)
- **Model** (`RAEquipment`, saved in the library): the rider's weight (75 kg when unknown), the default bike, the
  bikes (`RABike`: name, kind — road, hybrid, gravel, mountain, electric —, weight, riding position — upright, flat
  bar, hoods, drops —, CdA: typical value of the position, 0.55 / 0.45 / 0.36 / 0.30 m², unless corrected; Garmin gear
  id) and the parts (`RAPart`: tyre, chain, brake pads, cassette, other; model; width and wheel — front, rear, both —
  of a tyre; Crr; wear limit; mountings `RAMounting`: bike, from a day, to a day or still mounted).
- **Crr of a tyre**: corrected by the user, else the value of its model in the **tyre database** (owner's request),
  else an estimate by width (≤ 28 mm 0.0040 … > 45 mm 0.0070). Crr of a bike at a date: front tyre 40 %, rear 60 %
  (`crrOfBike:atDate:`), 0.005 when no tyre is known.
- **Tyre database** (`RATyreDatabase`, resource `RideAnalyzer/RATyres.plist`): 26 tyres (road, touring, gravel:
  Continental, Michelin, Schwalbe, Panaracer) with the Crr of the published drum tests of bicyclerollingresistance.com
  (29 km/h, 42.5 kg per tyre; Crr = watts / (speed × load)), the test width and pressure (collected 2026-11-21, from
  the figures quoted in search results). A model written by the user is matched to it ("GP5000" = Grand Prix 5000,
  the most specific name, then the nearest width). In the equipment window the model of a tyre is a combo box of the
  database (choosing one sets the model and width, the Crr then comes from the database; the tooltip of the Crr tells
  where the default comes from), and *Tyre Database…* opens a searchable table (`RATyreDatabaseWindowController`)
  whose *Use for Selected Part* gives a tyre to the selected part. Drum values on a smooth surface: real roads give
  more; the user corrects a tyre's Crr if needed. To add tyres: edit `RATyres.plist` (brand, model, variant, width,
  crr, pressure, category, source).
- **Rides and bikes**: `RARide.bikeID`; a new ride gets the default bike; setting a default bike gives it to the rides
  without one (same undoable change); contextual menu of the list *Bike ▸ …*; a *Bike* column; the filter has a
  bike criterion (pop-up of the sidebar; `RAFilter.bikeIDs`).
- **Distances and wear**: per bike, per part (the rides on its bike while it is mounted); a part over its limit is
  shown in the equipment window, and an alert after an import names it (once per part, `takeNewlyWornParts`).
- **Window** (Window ▸ Equipment, ⇧⌘E, toolbar "Equipment"; `RAEquipmentWindowController`): rider weight, default
  bike, tables of the bikes and parts (edited in place; Crr and CdA show their default in gray when empty). Changing
  the bike of a part already ridden moves it from today (its mounting ends yesterday); for a part never ridden it is
  a correction. Every change is undoable (`changeEquipment:actionName:` replaces the whole equipment).
- **Garmin Connect gear**: not available. The import of the bikes tried `gear-service/gear/filterGear` and got HTTP
  404 with the owner's key (2026-11-21). The Personal API serves a fixed list of 26 endpoints, and the gear is not
  among them: others report the same 404 for gear, devices and workouts. The button was removed, so bikes and parts
  are entered by hand. Only the Garmin Connect web session (#79, login in a `WKWebView`) could read the gear and the
  gear of each activity: an open question.
- **Equipment of each ride** (detail, owner's request): the bike of the ride (pop-up menu, undoable) and what was
  mounted on it at the ride's date (tyres with their wheel, other parts), with the mass, Crr and CdA of the
  estimated power. The estimated power shown is not recomputed until the ride is selected again.
- Not yet: the mounting history of a part beyond its last mounting (edited in the table), the bike criterion in the
  filter sheet (More…), a bike per device (e.g. the watch for commuting).

## Estimated power (2026-11-21, R11)
- **Model** (`RAPowerModel`): P = (m g sin θ + Crr m g cos θ + m a + ½ ρ CdA v_air |v_air|) v / η, v_air = v +
  headwind; negative values (braking, coasting) count as 0. m: rider + bike, Crr: the tyres on the bike at the ride's
  date, CdA: bike and position (R13; defaults 75 + 12 kg, Crr 0.005, flat bar 0.45 m² without equipment); ρ from the
  altitude and the temperature of the file (15 °C when none); η 0.97.
- **Wind** (`RAWind`, `RAWindProvider`: the wind at each point, speed and direction it comes from; headwind = speed ×
  cos(wind direction − heading)): already in the computations, nil (still air) until R12 gives it.
- **Detail** (R4): a ride without power meter gets its estimated power per point (speed over ~4 records for the
  acceleration): curve "Estimated power", colors by power, "Estimated power avg · max" (`useEstimatedPowers:`).
- **Trends** (R6): measures *Estimated power* and *Watts per beat, estimated power*. So that the trends do not read the
  files again, the stats keep per terrain the work sums of each force per unit (`gravityWork`, `rollingWork`,
  `inertiaWork` per kg, `airWork` per m² of CdA; stats version 3, computed again for older rides): the average power
  of a terrain is then (m (gravity + inertia) + m Crr rolling + CdA air) / η / time, with the equipment of each
  ride's date — a change of equipment applies at once. The clamping at 0 is per point in the detail but over the
  whole terrain in the trends (the descents are therefore not meaningful there).
- The estimate is computed for the rides shown (the filter, R3), e.g. those of the Edge, not those of the watch.
- Not yet: the wind (R12), the rider's weight from Garmin Connect, a calibration on rides with a power meter.

## Climbs (2026-11-21, R7)
- **Detection** (`RAClimbDetector`, with the stats of the ride: `RARideStats.climbs`, stats version 4, computed once):
  altitudes smoothed over 5 points; a climb goes from a low point to a high point as long as the road does not go
  down more than 10 m (or a quarter of the gain so far), starting where the road last leaves the bottom (within
  1.5 m: a flat or a small bump before it is not part of it); kept from 30 m of gain over 300 m or more at 3 % or
  more. Figures (`RAClimb`): start, end, km in the ride, length, gain, average and max gradient (over ~100 m), and the
  stats of its moving intervals: time, VAM, heart rate, measured power, work sums of the estimated power (R11).
- **Same climb** (`RAClimbGroup`): climbs of different rides starting and ending within 150 m of each other, lengths
  within 15 %; passages oldest first, best time, rank of a passage.
- **In the detail of a ride** (owner's choice, 2026-11-21, after a first version found unclear): its climbs are
  shaded on the profile (`ElevationProfileView.shadedRanges`, shared with BikePlanner, empty there) and drawn as
  an orange band under the track on the map. A table lists them: name (or "Climb n"), km, length, average and max
  gradient, gain, time, VAM, bpm, power (measured, or "≈" estimated), rank among the passages of the library
  ("2 of 5", ★ for the best, "first time"). A click zooms the profile, the curves and the map on the climb and
  puts the cursor at its foot; a double-click opens the Climbs tab on that climb.
- **Climbs tab** beside the list (Window ▸ Climbs, ⇧⌘K, toolbar "Climbs"; `RAClimbsViewController`), only to compare
  passages: the climbs of the selected rides (two or more) or of the list, the most ridden first. For the chosen
  climb: its passages
  (date, ride, time, VAM, bpm, power — measured, or "≈" estimated with the equipment of the ride's date —, rank) and
  the time of each passage against the date with its trend line (a click selects the passage).
- **Names**: a climb can be named in the table; the name is kept in the library with the climb's position
  (`nameOfClimb:` / `setName:ofClimb:`, undoable) and goes to every passage of the same climb.
- Not yet: the wind (R12) in their estimated power.

## Handoff (2026-11-21): written without Xcode, never compiled
The skeleton and the imports were written in a session without Xcode. First steps on the owner's Mac (Claude Code):
1. `git checkout ride_analyzer && git pull`.
2. Build `RideAnalyzer` (scheme `RideAnalyzer`, ad hoc signing as above) and fix the compile errors and warnings
   (#58: no warning, `analyze` clean). If Xcode rejects the project file, check the targets added by
   `scripts/xcode_add_target.py --type app / --type unit-test` (first use of these types).
3. Run `RideAnalyzerTests` (`RALibraryTests`, `RAImportTests`, `RAGarminConnectTests`, `RAFilterTests`,
   `RARideAnalysisTests`, `RAViewTests`, `RATrendsTests`), then the BikePlanner unit
   tests: shared sources changed (`GPXParser` reads `<time>`, `BPFITDecoder` reads `file_id` / sport,
   `BPTrackReader` gives `hasTimes`, device and sport; new tests in `GPXParserTests` and `BPTrackReaderTests`) and
   the project file changed: BikePlanner and its Quick Look extension must still build and pass.
   `RAZipReader` / the tests use the Compression library (`compression.h`): if the link fails, add
   `libcompression.tbd` to the RideAnalyzer target.
4. Launch the app (the owner): New Library, Import Files… (FIT / TCX / GPX, a folder), Import from Device…,
   drag and drop, the progress bar and Cancel, rename a ride and a device, delete, undo, save, reopen; search,
   Filter…, Save…, the saved filters in the sidebar; notes and tags; the detail (map colors, profile, curves,
   cursor). The window and the detail are built in code: their layout (stack views, split view, scroll view of
   the detail) is the most likely to need adjustments.
5. Garmin Connect (the owner, with his Personal API key): File ▸ Fetch from Garmin Connect…; check the points
   listed under "To check against the real Garmin service" above and adjust `RAGarminConnect` (and its stub in
   `RAGarminConnectTests`) to the real answers.
6. Also pending on `v10` (and therefore here): the new Garmin toolbar icon (#85, commit edb4c57) to check, then close
   #85.

## Open questions
- Gear of the rides from Garmin Connect (R13): not in the Personal API; through the web session (#79)?
- Name of the app (the target is `RideAnalyzer` for now).
- Map, profile and track display shared with BikePlanner (R4): which classes can be reused as they are
  (`ElevationProfileView`, `BikeMapView`…) and which need to be split from `MapController`.
- The historical weather service (R12).
