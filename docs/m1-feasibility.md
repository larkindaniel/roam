# M1 feasibility note — MapKit places, globe and geometry

Recorded 2026-10-13 during the M1 build. Runtime: **iOS 26.2 simulator only** (iPhone 17 Pro,
`3C864AD4-9C80-44BF-8B1C-EB57732C2C9C`), Xcode 26.3 (17C529). The app's deployment target is iOS 18.0,
but no iOS 18 runtime was used; iOS 18 behaviour is **not** verified here (deferred by the user).

## MapKit place resolution (live network test)

`RoamTests/MapKitFeasibilityTests` (run with `TEST_RUNNER_ROAM_LIVE_MAPKIT=1`; skipped otherwise).
Evidence log: `build/evidence/m1-mapkit-feasibility-*.log`.

| Check | Result |
|---|---|
| POI search "Golden Gate Park" near San Francisco | Resolved. `MKMapItem.identifier` = `I6020DC87BCD3874B` (iOS 18.0+ API), category `MKPOICategoryPark` → suggested **Outdoors**, locality San Francisco, region CA, country US, time zone America/Los_Angeles, postal address available |
| Identifier stability | Same identifier returned by a second search and round-tripped through `MKMapItemRequest(mapItemIdentifier:)` |
| Locality search "Hakone" | Resolved as a locality (no POI category, no street address) → suggested **Day Trips**, region Kanagawa, country JP. **No `identifier` is returned for localities.** |
| Destination search "Portland" | MapKit returned a single result (Portland, OR); same-name disambiguation therefore relies on region/country labels and typed context (e.g. "Portland Maine") |

Consequences adopted (see DECISIONS.md build-run log):

- Place identity: MapKit identifier first; otherwise exact normalized name + full address + six-decimal
  coordinates; never name alone (unchanged D24).
- **Localities have no identifier**, so a Day Trip locality is identified by its canonical city key
  (`country|region|locality`). Same-name localities in different regions stay distinct.
- Stored fields: identifier (when present), name, single-line address (from `MKPlacemark.postalAddress`),
  locality/region/country code and name, coordinate, phone, website, POI category raw value and time zone,
  plus provenance (`mapkit`). These are snapshot fields used to show the place and derive geography; Roam
  keeps the provider identifier for future re-resolution. Apple Maps attribution is shown by MapKit's own
  map views ("Maps" logo + Legal link). Before a hosted release, the Apple Maps/MapKit terms on caching
  place details must be re-checked; v1 stores only what is needed to show and dedupe the user's places.
- `MKMapItem.placemark` is deprecated in iOS 26 but available from iOS 18; Roam reads it on all versions so
  dedup keys are identical across OS versions (no deprecation warning at an 18.0 deployment target).
- Category suggestion table: `Roam/Places/PlaceCategoryMapper.swift` (iOS 18 POI categories). Unsupported
  POIs (e.g. banks) stay Uncategorized; the first logger confirms one of the seven categories.

## Globe rendering

- **Renderer:** `MKMapView` wrapped in `UIViewRepresentable` (`GlobeMapView`), because SwiftUI `Map` cannot
  cluster annotations. App structure stays SwiftUI.
- **3D globe:** MapKit draws the zoomed-out globe only for imagery configurations
  (`MKImageryMapConfiguration(elevationStyle: .realistic)`); `MKStandardMapConfiguration(.realistic)` stayed
  a flat projection at the same camera distance. Imagery uses realistic sun lighting, so part of the globe can
  be on the night side; country fills use a bright teal with a white outline so they read on both.
- **Shading:** visited countries are `MKPolygon` overlays built from bundled geometry; verified rendering on
  the simulator (Portugal, Denmark, Japan, Greenland, South Africa, US incl. Alaska).
- **Pins and clusters:** `MKMarkerAnnotationView` with a clustering identifier; tapping a cluster zooms to
  its members; selecting a pin reports the experience (and will open it with profile-owner context in M7).
- **Known limitation (timeboxed, revisit in M8):** on the iOS 26.2 simulator, globe annotation views rendered
  correctly only with the default whole-earth starting camera (25°N, 10°E). When the camera started centred
  elsewhere (e.g. on Japan), shading rendered but marker views did not. The globe therefore starts at that
  camera; members can rotate it, switch to **Flat map** (standard map, pins verified) or use the **List**
  alternative, which exposes the same data. XCUITest also lost the accessibility hierarchy while the
  interactive imagery globe was on screen. Not a substitution of the globe with a static illustration.

## Country geometry

- Source: **Natural Earth 1:110m Admin 0 – Countries, v5.1.2** (tag `v5.1.2` of
  `nvkelso/natural-earth-vector`), public domain (no permission needed; attribution optional, credited in
  Settings › About in M7). Original file SHA-256
  `6866c877d39cba9c357620878839b336d569f8c662d3cfab4cb1dbe2d39c977f`.
- Bundled as `Roam/Resources/Geo/countries-110m.geojson` (196 KB) after trimming to `iso_a2`, `name`,
  `adm0_a3` and geometry with coordinates rounded to 3 decimals.
- ISO mapping: `ISO_A2_EH` (assigns FR, NO, etc. where `ISO_A2` is `-99`). 175 countries keyed; N. Cyprus
  and Somaliland have no ISO code and are not shaded.
- Small states below 1:110m resolution (e.g. Singapore, Malta, Monaco) have no polygon: their pins render
  without shading (tested).
- Antimeridian: Natural Earth splits rings at ±180°. Unit tests assert no ring of FJ/RU/US spans more than
  180° of longitude and that Fiji has rings on both sides; pin identity across ±180° is tested.
