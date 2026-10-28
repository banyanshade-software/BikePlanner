# BikePlanner — Embedded BRouter engine (plan / spec)

Status: **proposal**, nothing implemented. This work is done on the branch `brouter` (kept for the whole project). Related issues: #2 (configurable / local BRouter
server), #1 (choice of the profile), #9 (routing errors are silent), #51 (secrets in the binary).

## 1. Goal and requirements

Run the BRouter routing engine **inside BikePlanner** instead of (or in addition to) the public `brouter.de` server.

| # | Requirement (owner) | Consequence |
|---|---|---|
| R1 | At least at first, the engine used must be easy to choose, **at build time or at run time** | One routing interface, two implementations (remote / embedded), selected by a build setting *and* a user default |
| R2 | **Everything in the application bundle** | The engine, its runtime, the profiles and lookup tables are in `BikePlanner.app`; no Java, Homebrew or server to install |
| R3 | Run on **somewhat old macOS versions** | Today `MACOSX_DEPLOYMENT_TARGET = 12.7` (Monterey): every embedded component must support macOS 12 |
| R4 | **Intel and Apple Silicon** (owner decision, 2026-10-29) | Every embedded component exists for x86_64 and arm64; the app stays universal |

Out of scope here: choosing the profile (#1), offline maps / tiles, Overpass.

## 2. Facts about BRouter (checked 2026-10)

- Java, MIT license, repository `abrensch/brouter`, built with Gradle; the server is compiled for **Java 11**
  (`options.release = 11`), so it runs on any Java ≥ 11.
- Stand-alone HTTP server: `java -cp brouter.jar btools.server.RouteServer <segmentdir> <profiledir>
  <customprofiledir> <port> <maxthreads> [bindaddress]`; serves `/brouter?lonlats=…&profile=…&format=gpx`
  (the API BikePlanner already uses), `/brouter/profile` (upload of custom profiles). System properties:
  `maxRunningTime` (s, default 60), `usePOSTRequests`, `maxRequestLength`. Default port in the scripts: 17777.
- The routing core (`btools.router.RoutingEngine`, `RoutingContext`, `OsmNodeNamed`…) can also be called directly
  from Java, without the HTTP server.
- Routing data: **segment files** `*.rd5`, one per 5°×5° tile named after the south-west corner
  (`E0_N45.rd5`…), rebuilt weekly from OSM, downloadable at `https://brouter.de/brouter/segments4/`. Sizes vary from
  a few KB (ocean) to **~250 MB** (dense European tiles; e.g. `E0_N40` ≈ 120 MB, `E5_N45` ≈ 253 MB). The planet is
  several GB. Data is ODbL: OSM attribution required.
- Profiles: `profiles2/*.brf` + `lookups.dat` (small, a few hundred KB in total).

Sources: https://github.com/abrensch/brouter (README, `RouteServer.java`, `buildSrc/…/brouter.java-conventions.gradle`),
https://brouter.de/brouter/segments4/.

## 3. Options to run BRouter in the app

| | A. Bundled JRE + `brouter.jar`, local HTTP server | B. GraalVM native image of BRouter | C. Port of the routing core to Objective-C / Swift | D. JVM inside the app process (JNI) |
|---|---|---|---|---|
| Effort | **low** (no change to BRouter, reuse `BRouterClient`) | medium (native-image config, two builds) | very high (BRouter ≈ tens of thousands of lines, profile language) | high |
| Size in bundle | runtime trimmed with `jlink` ≈ 40–50 MB **per architecture** + jar ≈ 1 MB | executable ≈ 20–40 MB per arch | small | as A |
| macOS 12 | Temurin / OpenJDK 17 and 21 support macOS 11+ (x64 and aarch64) → OK | depends on GraalVM release and build SDK → **to verify** | OK | as A |
| Startup | JVM start ≈ 0.3–1 s, once (server kept alive) | ≈ instant | instant | once |
| Sandbox / hardened runtime | child process inherits the sandbox; JIT needs `com.apple.security.cs.allow-jit` (hardened runtime / notarization) | no JIT, simplest for notarization | none | JVM in-process: JIT + library validation issues |
| Following BRouter updates | replace the jar | rebuild native image | manual port | replace the jar |
| Risk | low | reflection / resources config, BRouter not tested as native image | very high | high |

**Decision: A** (fast, reliable, no fork of BRouter), with the engine behind an interface. B (GraalVM native image)
is not pursued (owner, 2026-10-29); C and D are rejected.

### 3.1 Option A in detail

- **Runtime**: `jlink --add-modules java.base,java.logging,…(minimum found with jdeps) --strip-debug --no-man-pages
  --no-header-files --compress=zip-6` from a Temurin 17 LTS JDK (macOS 11+), once for **aarch64** and once for
  **x64**. Both are bundled (`Contents/Resources/brouter/jre-arm64`, `…/jre-x64`, ≈ 90 MB in total) and the app
  starts the one matching the running architecture (R4; a universal JRE does not exist). Two thin apps (one per
  architecture) remain a fallback only if the size of the universal app becomes a problem (see §8).
- **Engine**: `brouter.jar` (server + core) built from a pinned BRouter tag (e.g. 1.7.x) by a script
  (`scripts/build_brouter.sh`: clone/checkout tag, `./gradlew :brouter-server:fatJar` or equivalent, copy the jar),
  committed as a build input or downloaded and checksum-verified at build time — not rebuilt by Xcode at each build.
- **Profiles**: `profiles2/` (trekking, fastbike, safety, shortest, …) + `lookups.dat` from the same BRouter tag, in
  `Contents/Resources/brouter/profiles2/`. Custom profiles (Params tab overrides are URL parameters, no file needed)
  in the app container.
- **Process**: launched with `NSTask` (or `posix_spawn`) as
  `jre-<arch>/bin/java -Xmx512m -DmaxRunningTime=60 -cp brouter.jar btools.server.RouteServer
  <segments> <profiles2> <customprofiles> <port> 1 127.0.0.1`, bound to **127.0.0.1 only**, on a free port chosen by
  the app (try 17777, else a random free port). Started lazily at the first route request (or at launch, to hide
  the JVM start), stopped when the app quits (`applicationWillTerminate`, plus the child dies with the parent:
  watchdog on stdin/pipe close, since a sandboxed app cannot rely on process groups). Health check:
  request a tiny route or poll the port until it answers; restart once on crash; logs to the app container.
- **Communication**: plain HTTP on loopback → the existing `BRouterClient` is reused unchanged
  (`serverURL = http://127.0.0.1:<port>`). Needs the **`com.apple.security.network.server`** entitlement (listening
  socket) in addition to `network.client`. Alternative without listening socket: a small Java main (`stdin/stdout`
  JSON protocol calling `RoutingEngine` directly) — more code on both sides; keep as a fallback if
  `network.server` is a problem.
- **Signing**: every executable/dylib of the JRE must be signed with the app (Xcode "Copy Files" phase + code sign
  on copy, or a script phase `codesign --force --sign … --options runtime --entitlements jre.entitlements`); the
  `java` executable needs `com.apple.security.app-sandbox` + `com.apple.security.inherit` (child of a sandboxed
  app), and, with the hardened runtime (notarization, doc/03), `com.apple.security.cs.allow-jit`. Ad hoc signing
  (`CODE_SIGN_IDENTITY=-`, this machine) must keep working.

## 4. Segment files (routing data)

The planet (several GB) cannot be bundled. R2 is read as: **everything needed to run the engine is in the bundle**;
the map data is per region:

Decision (owner, 2026-10-29): **tiles are downloaded on demand and kept in a local cache**; no tile is bundled.

- **Download on demand, cached**: when a route needs a tile that is missing (computed from the waypoints'
  bounding box + margin: 5° tiles), the app downloads it from `https://brouter.de/brouter/segments4/` into
  `~/Library/Containers/<bundle id>/Data/Library/Application Support/BikePlanner/segments4/`, with progress UI,
  resume, checksum/size check, and an update check (tiles are rebuilt weekly; update when older than N weeks,
  user-triggered). The engine is restarted or simply re-reads the directory (BRouter opens segment files on demand).
- The cache is kept between launches (Application Support, not Caches: tiles are large and slow to download, the
  system must not purge them); the user can delete tiles from the routing data panel. Update policy (tiles are
  rebuilt weekly): to define in phase 4 (e.g. offer an update when a tile is older than a few weeks).
- *(Not planned)* bundling tiles in the app (`BP_BUNDLED_SEGMENTS` build option) — kept only as an idea for a fully
  offline build.
- A "Routing data" panel (Preferences, #27): list of tiles, size, date, delete / update.
- Missing tile and no network → clear error (#9), and the remote engine can be offered as fallback.

## 5. Choosing the engine (R1)

### 5.1 Interface

```objc
@protocol BPRoutingEngine <NSObject>
@property (readonly) NSString *name;                 // "brouter.de", "embedded BRouter"
- (void)routeWithWaypoints:(NSArray<CLLocation *> *)waypoints profile:(NSString *)profile
                 overrides:(nullable NSDictionary<NSString *, NSString *> *)overrides
                completion:(void (^)(NSArray<CLLocation *> *points, NSData *gpx, NSDictionary *info, NSError *error))completion;
- (nullable NSURL *)profileURLForName:(NSString *)profile;   // Params tab (.brf download / file in the bundle)
@end
```

- `BPRemoteBRouterEngine`: today's behavior (`BRouterClient` on `BPEnvironment brouterServerURL`, i.e. brouter.de
  or the server of #2).
- `BPEmbeddedBRouterEngine`: owns the process (§3.1) and the segments (§4), then delegates to a `BRouterClient` on
  `http://127.0.0.1:<port>`; `profileURLForName:` returns the `.brf` file in the bundle (file URL).
- `MapController` (`self.brouter`) and `BRFProfileEditor` (`BPEnvironment brouterProfileURLForName:`) use the
  engine returned by a single factory, `+[BPRoutingEngines currentEngine]`, instead of creating `BRouterClient`
  themselves.

### 5.2 Selection

- **Build time**: build setting `BP_EMBEDDED_BROUTER` (YES/NO) in an `.xcconfig`, exposed as a preprocessor macro
  and as an Info.plist key (`BPEmbeddedBRouterAvailable`). With NO, the JRE / jar / profiles are not copied and the
  embedded engine class is compiled out → small app identical to today. Two schemes: `BikePlanner` (remote only)
  and `BikePlanner Embedded` (both engines).
- **Run time**: user default `BPRoutingEngine` = `remote` | `embedded`. Decision (owner, 2026-10-29): the **local
  (embedded) engine is the default**; the remote engine is an option (default `embedded` when available, else
  `remote`), settable from Preferences (#27), from a temporary menu item (Debug ▸ Routing Engine) until #27 exists,
  and from the command line / tests like the other `BPEnvironment` keys (`-BPRoutingEngine remote`).
- Changing the engine recomputes the current route (same as Apply in the Params tab). The engine in use is shown
  (Info section or window subtitle), and recorded in the Info.plist build info for the About window
  (`Version 0.8.0 (Build …, embedded BRouter 1.7.x)`).
- Not saved in the document (a machine choice, not a plan property).

## 6. Compatibility (R3)

- Deployment target stays **12.7**; the app stays universal. Component checks:
  - JRE: Temurin 17 LTS (macOS 11+, x64 and aarch64) — pick the version and verify `java -version` on a macOS 12 VM
    for both architectures (Rosetta is not needed: native JRE per arch).
  - BRouter jar: Java 11 bytecode → OK on 17.
  - `NSTask`, sandbox inheritance, loopback server: available on macOS 12.
- Test matrix before release (R4: both architectures, each with its own JRE): macOS 12 Intel, macOS 12/13 Apple
  Silicon, current macOS on both; fresh user account
  (sandbox container created), no network (bundled tiles only), first launch (JVM start time).

## 7. Testing (everything offline, as today)

- Unit tests keep using `BPStubServer` through the **remote** engine (`-BPRoutingEngine remote`).
- Engine selection: unit tests of the factory (build flag × user default × availability).
- Embedded engine, process management: tests with a fake `java` (a script answering on the port) for start, port
  choice, health check, crash/restart, stop at quit — no JVM needed.
- Real embedded routing (opt-in test target or scheme, not in the default unit tests: needs the JRE and a segment):
  a **tiny test segment** generated once from a small OSM extract with BRouter's map creator (a few KB, committed in
  `BikePlannerTests/brouter/`), route between two points, compare length / time with the values recorded from
  brouter.de for the same data.
- Segment download: stub server answering `/brouter/segments4/<tile>.rd5` (extend `BPStubServer`).
- Bundle checks (script): JRE present for both archs, all Mach-O files signed, `codesign --verify --deep`, app
  launches the engine from the DMG (#37) on a clean account.

## 8. Open questions (owner)

1. ~~Architectures~~ — **decided**: Intel and Apple Silicon (R4). Default packaging: one universal app with both
   JREs (≈ +90 MB, DMG compressed ≈ +40 MB); two thin apps only if this size is a problem.
2. ~~Segments~~ — **decided**: downloaded on demand and kept in a local cache (§4). Update policy: phase 4.
3. ~~Default engine~~ — **decided**: local (embedded) by default, remote as an option (§5.2).
4. Keep the remote engine in the long term? Not decided — probably yes (fallback, machines without the data).
5. `network.server` entitlement (loopback HTTP) or stdin/stdout bridge (§3.1)? To define later, not important now
   (phase 0 uses loopback HTTP).
6. ~~GraalVM native image~~ — **decided**: no.

## 9. Phases

| Phase | Content | Done when |
|---|---|---|
| 0 | Spike (throw-away branch off `brouter`): run `RouteServer` with a jlinked JRE launched by the sandboxed app on this Mac, route on one tile; also run the x64 JRE under Rosetta to check the Intel path | a route computed by the embedded server is shown in the app, with both JREs |
| 1 | `BPRoutingEngine` protocol, `BPRemoteBRouterEngine`, factory, `BPRoutingEngine` user default; MapController / BRFProfileEditor go through it (no behavior change) | all tests pass, remote behavior unchanged |
| 2 | Build pipeline: `scripts/build_brouter.sh` (pinned BRouter tag → jar + profiles), `scripts/build_jre.sh` (jlink, both archs), Xcode copy + sign phases, `BP_EMBEDDED_BROUTER` build setting and scheme | `codesign --verify --deep` OK, app size known, remote-only build unchanged |
| 3 | `BPEmbeddedBRouterEngine`: process lifecycle, port, health check, logs, errors (#9) | route with a manually installed tile, tests with fake `java` |
| 4 | Segments: tile computation, download with progress, storage, update, optional bundled tiles | route in a new region downloads the tile once |
| 5 | UI: engine choice (temporary menu, then Preferences #27), engine shown in Info / About, routing data panel | owner can switch engines at run time |
| 6 | Packaging: DMG (#37) with the embedded engine, hardened runtime entitlements, test on macOS 12 (Intel + Apple Silicon), docs (01, 02, 03, CLAUDE.md) | DMG works on a clean macOS 12 account offline (bundled tile) |

Each phase is a separate PR-sized step on the `brouter` branch, with its issue.
