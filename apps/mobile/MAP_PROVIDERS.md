# Map provider boundary

The existing Google navigation flow remains available. A second Mapbox Maps
renderer is selected in Settings without restarting the app. `main.dart` still
owns the Google Navigation SDK controllers, so this is an incremental boundary,
not a claim that every legacy Google type has already been removed from the
screen coordinator.

## Product models and adapters

- `domain/map_provider.dart`: `GeoPoint`, `PlaceSummary`, `ProviderReference`,
  `SelectedPlace`, `MapViewportState`, provider capability/policy decisions.
- `domain/route_option.dart`: provider-neutral route geometry, steps and route
  options. Google `LatLng` conversion happens only where the SDK is called.
- `providers/provider_contracts.dart`: map, search, place, Explore, routing and
  navigation interfaces.
- `providers/google_map_renderer.dart`: existing Google browse map adapted to
  neutral viewport, POI, long-press and pan events without changing native
  Google turn guidance.
- `providers/place_search_providers.dart`: existing Worker/Geoapify search for
  Google, Mapbox Search Box for Mapbox. Search Box suggestions are retrieved
  before becoming a selected place; reverse lookup enriches Mapbox POI taps.
- `providers/mapbox_routing_provider.dart`: Mapbox Directions routes and
  alternatives. New Zealand traffic availability is not assumed.
- `providers/mapbox_map_renderer.dart`: Mapbox camera, native location puck,
  selected/Explore markers, safety camera overlays and route polyline.
- `providers/mapbox_navigation_engine.dart`: GPS/route-step guidance with the
  existing independent `DriveEngine` safety-camera alerts. This is not the
  Mapbox Navigation SDK and does not yet provide native rerouting or lanes.

Provider references are checked before showing content on a map. Google Places
or Worker/Geoapify POI content is not silently shown on Mapbox. Search Box
results and Mapbox routes remain session-scoped because persistent storage
needs a separate Mapbox entitlement. Switching providers preserves the camera
and destination coordinate, then re-resolves a place via the new provider where
possible. Home/Work selected from Mapbox search are session-only for the same
reason.

## Configure Mapbox

Pass a public `pk.` Mapbox access token when building or running Flutter:

```bash
flutter run --dart-define=MAPBOX_ACCESS_TOKEN=YOUR_PUBLIC_TOKEN
flutter build apk --dart-define=MAPBOX_ACCESS_TOKEN=YOUR_PUBLIC_TOKEN
```

For local development, put `{"MAPBOX_ACCESS_TOKEN":"pk..."}` in the ignored
`apps/mobile/.dart-defines.local.json`, then run from `apps/mobile`:

```bash
flutter run --dart-define-from-file=.dart-defines.local.json
flutter build apk --dart-define-from-file=.dart-defines.local.json
```

CI and release builds should supply the public token as a build variable. This
Maps SDK integration does not currently request a private Mapbox SDK download
token. A future native Navigation SDK could require a separate `sk.` download
token stored only in local Gradle properties or CI secrets; never pass that
secret through `--dart-define` or embed it in the app.

If no public token is provided, Settings explains why Mapbox cannot be
selected and a previously selected Mapbox map falls back to Google. Existing
Google Maps platform key setup is unchanged. iOS deployment target remains
16.0; Android remains API 24+.

## Remaining verification

The Android debug APK builds, Flutter analysis and unit/widget tests pass.
Google and Mapbox live map taps, permission changes, lifecycle/resume, Chinese
results, and native iOS builds require instrumented device testing with valid
provider credentials. Native Mapbox Navigation SDK capabilities and measured
along-route detour times remain future adapter work; the UI does not invent
traffic or detour figures for unsupported regions.
