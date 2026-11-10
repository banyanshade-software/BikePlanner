# BikePlanner — Constraints for a Wider Distribution

Status: BikePlanner is a **personal** application today. This document lists what would have to be checked or
changed before distributing it to other people (direct download, notarized build, or Mac App Store).
It is a checklist, not legal advice: terms of service change, and each item must be re-checked against the
provider's current terms at the time of distribution. Tracked by
[#20](https://github.com/banyanshade-software/BikePlanner/issues/20).

**Summary (status 2026-11-09, version 0.9.5)** — The app is not ready to be shared. Done: location usage string
(and the location is asked only when the user chooses *My location* as start position, #65), keys kept out of git
and obfuscated in the binary (#51), Street View through the Maps Embed API when a key is set (#49, the key is checked
first), a Credits text in the About window and exact attributions in the README (#64), an identifying User-Agent on
every request, Overpass backoff and smaller queries (#12), a build without compiler or analyzer warnings (#58).
Still missing: on-map attributions (OSM, Thunderforest), the exact attributions in the About window, a better
protection of the keys (#57), a user-configurable BRouter server (#2), a license decision for distribution (today
all rights reserved), and Developer ID signing + notarization. The volunteer-run public services (OSM tiles, brouter.de, overpass-api.de) cannot back a distributed
app anyway: each needs its own server, a paid provider, or a per-user setting.

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
- **Billing**: the Maps Embed API is free with unlimited usage
  ([Usage and Billing](https://developers.google.com/maps/documentation/embed/usage-and-billing)), but the project
  needs a billing account, and the key can be extracted from the binary (or read in the iframe URL). The risk is a
  stolen key used for paid Google Maps Platform APIs. Protections: a project dedicated to BikePlanner with only the
  Maps Embed API enabled; the key restricted to the Maps Embed API (the main protection) and to the referrer
  `https://bikeplanner.invalid/*` (can be spoofed); a 1 € budget with e-mail alerts (alerts only, it does not cap
  spending); optionally a lower daily quota on the Maps Embed API; a monthly look at the billing reports. Steps in
  the console (in French): `doc/google-maps-embed-facturation.md`; creating the key: `doc/get_google_api_key.md`.
- Alternatives without Google: Mapillary (CC-BY-SA imagery, API key), Panoramax (open).

### 1.2 OpenStreetMap tiles (`tile.openstreetmap.org`)
- Governed by the **OSM Tile Usage Policy**: tiles are a donated service for light use; heavy use or apps
  with many users are not allowed to rely on them.
- Requirements even for light use: a **valid, identifying HTTP User-Agent** (app name + contact), honoring HTTP
  caching headers (no bulk download / pre-fetching), and the visible attribution **“© OpenStreetMap contributors”**.
- **Today**: tiles are loaded by `SafeOSMTileOverlay -loadTileAtPath:result:` (`NSURLSession`, whose cache honors
  the caching headers) with the app's User-Agent `BikePlanner/<version> (build <n>; +<GitHub URL>)`
  (`+[BPEnvironment userAgent]`, sent on every request of the app); no attribution on the map (only in the About
  window Credits).
- **To do**: display the attribution on the map, and for real distribution use a commercial/self-hosted tile provider.

### 1.3 Thunderforest (OpenCycleMap)
- Requires an API key; the free “Hobby Project” tier has a monthly tile limit and is for non-commercial use.
- A key embedded in a distributed binary can be extracted and abused (it is billed to the owner). Since #51 it is
  stored obfuscated (`BPSecrets`; not visible with `strings`), more strongly since #57 (keystream seeded by the
  compile time, bytes out of order, split in two shares; no simple decoding finds it, checked by `SecretsTests` and
  `make_dmg.sh`): this raises the cost of extraction only — the key is sent in clear in every tile request and can
  be read by anyone debugging the app.
- Attribution: “Maps © Thunderforest, Data © OpenStreetMap contributors” — **today** only “provided by
  thunderforest.com” in the About window Credits, nothing on the map.
- **To do**: pick the right plan, display the attribution; consider letting each user enter their own key
  (stored in the Keychain) instead of compiling it in `Secret.h`.

### 1.4 BRouter (`brouter.de`)
- The public server is run by a volunteer for light use; it is not meant as a backend for a distributed app.
- BRouter itself is MIT-licensed open source and can be run locally (Java) — this is already the long-term
  target (local server). For distribution: either bundle/install a local BRouter (Java runtime, segment files of
  several GB per region) or let the user configure their own server.
- Routing data is derived from OSM (ODbL): attribution required.
- **Today**: `https://brouter.de` by default; another server can only be set with the hidden user default
  `BPBRouterServer` (the test hook of `BPEnvironment`), not in the Preferences. Identifying User-Agent (see 1.2).
- **To do**: server in the Preferences ([#2](https://github.com/banyanshade-software/BikePlanner/issues/2), embedded
  engine on branch `brouter`).

### 1.5 Overpass API (`overpass-api.de`)
- Public instances have usage limits (roughly: a few requests at a time per IP, daily volume guidance) and ask
  for reasonable use; heavy queries are rejected (HTTP 429/504).
- **Today**: one query per route change, throttled to ≥ 2.8 s; `around` clauses per route point sampled every
  ≥ 1 km (at most 300 points; a single `around` along a polyline returned nothing on overpass-api.de); after an error, retries with exponential backoff (2, 4, 8… s) or the server's
  `Retry-After` (429/503), at most 5, then nothing until the next route change
  ([#12](https://github.com/banyanshade-software/BikePlanner/issues/12)); identifying User-Agent (see 1.2).
- **To do**: for very long routes, split the query (300 points × 2 clauses may still be heavy); for
  distribution, a private Overpass instance
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

**Today**: the README has the exact attributions (#64: OSM/ODbL, Thunderforest, Apple MapKit, BRouter, Overpass,
Google Street View, Maki CC0, DCOAboutWindow BSD) and a copyright notice (© 2025–2026 Daniel Braun, all rights
reserved; also `NSHumanReadableCopyright`); the About window shows `Base.lproj/Credits.rtf` (services used, Maki
icons, DCOAboutWindow; its Street View sentence predates #49). To do in the About window:
the exact attribution texts (“© OpenStreetMap contributors”, ODbL; “Maps © Thunderforest”; Google), BRouter (MIT)
if bundled, and a check of each icon's origin.

## 3. Apple platform requirements

- **Code signing & notarization**: needed for any distribution outside the Mac App Store (Developer ID).
  **Today**: ad hoc signature; `scripts/make_dmg.sh` builds a DMG (#37) that is not notarized (its Read Me explains
  how to open it the first time). Needs a paid Apple Developer account.
- **App Sandbox**: already enabled (network client, user-selected files, location). A bundled local BRouter
  server would need either an XPC/helper or a separate install.
- **Location usage description** ✅: `NSLocationWhenInUseUsageDescription` is a real sentence (“BikePlanner centers
  the map on your location when you start planning a route.”).
- **Privacy**: the user location is asked only when *Preferences ▸ Start position* is *My location* (the default
  is a remarkable site at random, #65). Requests to Google, OSM, Thunderforest and Overpass reveal the user's area of interest; a privacy
  policy is required for the App Store and is good practice anyway. App Store also requires a privacy manifest
  if required-reason APIs are used.
- **Mac App Store**: in addition, the review would likely reject the embedded Google Maps web page (see 1.1:
  still used when no Google Maps key is set).

## 4. Secrets

- API keys must never be committed (already handled by `Secret.h` + `.gitignore`). Keys compiled in are obfuscated
  (`BPSecrets`, #51, stronger encoding #57) and `scripts/make_dmg.sh` refuses an app with a key in clear or found by
  a simple decoding (reversed, XOR with one byte, the fixed mask of #51).
- Any key compiled into a distributed app is public in practice. Decision for #57 (November 2026): stronger
  obfuscation only, the keys stay in the DMG, which therefore is still not shared; per-user keys (Preferences +
  Keychain) or a server-side proxy remain the options if the app is ever distributed.

## 5. Checklist — minimum set before sharing the app with anyone

| # | Item | Status | Issue |
|---|---|---|---|
| 1 | Street View through an official Google API (or an alternative provider) | 🟡 Maps Embed API when a key is set; drop the Google Maps web app fallback | #49 |
| 2 | Identifying User-Agent + “© OpenStreetMap contributors” on the map for OSM tiles | 🟡 User-Agent done; attribution missing | — |
| 3 | Thunderforest attribution and key strategy (per-user key in Keychain?) | 🟡 key obfuscated (stronger since #57); no attribution on the map | #51, #57 |
| 4 | Overpass backoff, User-Agent, smaller queries | ✅ | #12 |
| 5 | Configurable BRouter server (local or the user's own) | 🟡 hidden default only | #2 |
| 6 | Real location usage string; acknowledgments in the About window | ✅ string (location asked only for *My location*, #65); 🟡 exact attributions in the README, not yet in the About window | #64 |
| 7 | Developer ID signing + notarization | ❌ ad hoc signing, DMG not notarized | #37 |
| 8 | License of the app and of the source | 🟡 all rights reserved (README, #64); to decide before distributing | #64 |
