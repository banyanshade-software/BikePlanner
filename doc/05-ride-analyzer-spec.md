# Ride Analyzer — Specification (draft)

A second macOS app, next to BikePlanner, that fetches the rides actually done and analyses them (#82).
Branch `ride_analyzer`, from `v10`. Each feature below is proposed, then accepted (or not) by the owner.

Status: **draft** — feature list reviewed with the owner on 2026-11-21 (R1–R14); no design yet.

## Features

### R1 — Fetch rides from Garmin Connect *(accepted 2026-11-21)*
- The Garmin Connect Personal API key is obtained in the embedded browser, in the user's Garmin Connect session
  (the web part of #79, *Settings ▸ Personal API token*), then kept in the Keychain. No key in the app.
- The app lists the user's cycling activities, downloads their FIT files and, on later launches, fetches only the
  new ones.
- The raw FIT files are kept locally.
- **Also useful in BikePlanner**: *Import Track as Display…* / *Import Track as Route…* (F8.1, F8.3) can import an
  activity directly from Garmin Connect, instead of exporting it as a GPX / TCX / FIT file first.

### R2 — Import rides from local files *(accepted 2026-11-21)*
- FIT, GPX or TCX files, by drag and drop or the File menu (reuses the parsers of BikePlanner: `BPFITDecoder`,
  `GPXParser`).
- Direct import from the bike computer connected by USB (its `Garmin/Activity` folder).
- A ride already fetched from Garmin Connect (R1) is recognized and skipped (no duplicates).

### R3 — Ride library *(accepted 2026-11-21)*
- A list of all the rides: date, name, distance, ascent, duration, average speed.
- Sortable; filter by period; search by name.
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

### R7 — Climb analysis *(accepted 2026-11-21)*
- Automatic detection of the climbs of a ride: length, ascent, average and max gradient, with time, climbing speed
  (VAM) and heart rate.
- A climb ridden again is compared with the previous passages (best time, trend).

### R8 — Road types and surfaces *(accepted 2026-11-21, postponed to a later version of the app)*
- For a ride: distance and time per road type (cycleway, tertiary road, track…) and per surface (asphalt,
  gravel…), with the average speed on each; reuses the *Road types* display of BikePlanner (#66).
- Types from OpenStreetMap: the track is matched to the roads (through BRouter or Overpass).

### R9 — Export and sharing *(accepted 2026-11-21)*
- Export a ride as GPX, optionally cleaned up: pauses removed, start and end trimmed near home.
- Export the library or the statistics as CSV, for a spreadsheet.
- An image of the ride (map, profile, key figures) to share.

### R10 — Map of all rides (heatmap) *(accepted 2026-11-21)*
- All the tracks drawn on one map; the most ridden roads stand out. Filter by period.
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

### R12 — Weather of the ride *(accepted 2026-11-21)*
- Wind (speed, direction) and temperature from a historical weather service, for the date and place of the ride.
- Shown in the ride detail (R4); used by the estimated power (R11) and to explain a speed (headwind, tailwind).
- The service is to be chosen (free, no key in the app, terms compatible): routed through an environment hook like
  the other endpoints of BikePlanner.

### R13 — Equipment tracking *(accepted 2026-11-21)*
- From the bikes and tyres entered for R11: distance per bike and per part (tyres, chain, brake pads…).
- A wear threshold per part, and a reminder when it is reached.

### R14 — Heart rate and power zones *(accepted 2026-11-21)*
- Time in each zone, for a ride and over a period.
- From the max heart rate and the power threshold (FTP), entered or taken from Garmin Connect.
- With the estimated power (R11) when there is no power meter.

## Related BikePlanner items
- Import an activity directly from Garmin Connect as display or as route (R1).
- Planned vs. done comparison (R5): a BikePlanner feature, #88.

## Open questions
- How the code is shared with BikePlanner (common framework, or shared sources in both targets): Garmin Connect web
  session (#79), FIT / GPX / TCX parsers, map and track display, elevation profile, road types (#66).
- Name of the app.
- Where the library is stored (database file, or a folder of FIT files plus an index).
- The historical weather service (R12).
