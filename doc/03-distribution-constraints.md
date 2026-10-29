# BikePlanner — Constraints for a Wider Distribution

Status: BikePlanner is a **personal** application today. This document lists what would have to be checked or
changed before distributing it to other people (direct download, notarized build, or Mac App Store).
It is a checklist, not legal advice: terms of service change, and each item must be re-checked against the
provider's current terms at the time of distribution.

---

## 1. Third-party services

### 1.1 Google Street View
- **Today** (#49): with `GOOGLE_MAPS_API_KEY` in `Secret.h`, the app shows the **Maps Embed API**
  (`https://www.google.com/maps/embed/v1/streetview?key=…&location=…&heading=…`) in an iframe of a local page;
  without a key, it still loads the Google Maps web app (`https://www.google.com/maps/@?api=1&map_action=pano&…`).
- **Constraint**: the Google Maps URL scheme is meant to *open Google Maps*; embedding the Google Maps web
  application inside a third-party app is generally not covered by Google's terms. The supported ways to embed
  Street View are the **Maps Embed API** (iframe, API key, free tier) or the **Maps JavaScript API** (API key, billing account).
- **To do before distributing**: require the Maps Embed API (drop the fallback to the Google Maps web app); manage
  the API key (restricted to the Maps Embed API and the referrer `https://bikeplanner.invalid/*`; it is obfuscated in
  the binary like the Thunderforest key, but sent in clear in the iframe URL); quotas (the Embed API is free).
- Alternatives without Google: Mapillary (CC-BY-SA imagery, API key), Panoramax (open).

### 1.2 OpenStreetMap tiles (`tile.openstreetmap.org`)
- Governed by the **OSM Tile Usage Policy**: tiles are a donated service for light use; heavy use or apps
  with many users are not allowed to rely on them.
- Requirements even for light use: a **valid, identifying HTTP User-Agent** (app name + contact), honoring HTTP
  caching headers (no bulk download / pre-fetching), and the visible attribution **“© OpenStreetMap contributors”**.
- **Today**: tiles are loaded by `MKTileOverlay` with the default User-Agent, and no attribution is displayed.
- **To do**: set a User-Agent (custom `loadTileAtPath:result:` using an `NSURLSession` with headers), display the
  attribution on the map, and for real distribution use a commercial/self-hosted tile provider.

### 1.3 Thunderforest (OpenCycleMap)
- Requires an API key; the free “Hobby Project” tier has a monthly tile limit and is for non-commercial use.
- A key embedded in a distributed binary can be extracted and abused (it is billed to the owner). Since #51 it is
  stored obfuscated (`BPSecrets`, XOR at compile time; not visible with `strings`): this stops a casual look only —
  the key is sent in clear in every tile request and can be read by anyone debugging the app.
- Attribution: “Maps © Thunderforest, Data © OpenStreetMap contributors”.
- **To do**: pick the right plan, display the attribution; consider letting each user enter their own key
  (stored in the Keychain) instead of compiling it in `Secret.h`.

### 1.4 BRouter (`brouter.de`)
- The public server is run by a volunteer for light use; it is not meant as a backend for a distributed app.
- BRouter itself is MIT-licensed open source and can be run locally (Java) — this is already the long-term
  target (local server). For distribution: either bundle/install a local BRouter (Java runtime, segment files of
  several GB per region) or let the user configure their own server.
- Routing data is derived from OSM (ODbL): attribution required.

### 1.5 Overpass API (`overpass-api.de`)
- Public instances have usage limits (roughly: a few requests at a time per IP, daily volume guidance) and ask
  for reasonable use; heavy queries are rejected (HTTP 429/504).
- **Today**: one query per route change, throttled to ≥ 2.8 s, retried every ~2 s on errors without backoff.
- **To do**: exponential backoff, respect `429`/`Retry-After`, smaller queries (route bounding corridor instead of
  one `around` clause per sampled point), identifying User-Agent; for distribution, a private Overpass instance
  or caching layer. Data is OSM (ODbL): attribution required.

### 1.6 Apple MapKit
- Free for apps on Apple platforms within normal use; Apple maps attribution is handled by `MKMapView`.
- `MKLocalSearch` is subject to Apple's throttling.

## 2. Licenses and attribution

| Item | License / requirement |
|---|---|
| OSM data (tiles, Overpass, BRouter routes) | ODbL — “© OpenStreetMap contributors” visible |
| POI icons (`Assets.xcassets/icon_*`) | From mapbox/maki (CC0) — check each icon's origin (code comments also mention Flaticon icons, which require attribution) |
| DCOAboutWindow (`DCO/`) | See `DCO/LICENSE` — keep the license notice |
| BRouter (if bundled) | MIT |

An *Acknowledgments* section in the About window would cover the attributions.

## 3. Apple platform requirements

- **Code signing & notarization**: needed for any distribution outside the Mac App Store (Developer ID).
- **App Sandbox**: already enabled (network client, user-selected files, location). A bundled local BRouter
  server would need either an XPC/helper or a separate install.
- **Location usage description**: `NSLocationWhenInUseUsageDescription` is currently `"1"`; it must be a real
  sentence explaining why the location is used.
- **Privacy**: requests to Google, OSM, Thunderforest and Overpass reveal the user's area of interest; a privacy
  policy is required for the App Store and is good practice anyway. App Store also requires a privacy manifest
  if required-reason APIs are used.
- **Mac App Store**: in addition, the review would likely reject the embedded Google Maps web page (see 1.1).

## 4. Secrets

- API keys must never be committed (already handled by `Secret.h` + `.gitignore`).
- Any key compiled into a distributed app is public in practice: prefer per-user keys or a server-side proxy.

## 5. Summary — minimum set before sharing the app with anyone

1. Street View through an official Google API (or an alternative provider).
2. Identifying User-Agent + attribution for OSM tiles; Thunderforest attribution and key strategy.
3. Overpass backoff and User-Agent.
4. Configurable BRouter server (local server or the user's own).
5. Real location usage string, About window acknowledgments, Developer ID signing + notarization.
