# Map provider boundary

Google Maps Navigation is the only implemented map/navigation provider. Mapbox is intentionally not enabled yet.

Camera data comes from the Worker through `CameraRepository`. Camera selection and alert timing live in `DriveEngine`, `CameraMatcher`, and `RouteCameraMatcher`; they must not move into a map widget. The Google-specific marker artwork and registration live in `widgets/map_symbols.dart`. `main.dart` currently adapts camera data to Google marker and polyline APIs.

When adding Mapbox, introduce a map-view adapter for camera markers, route traffic segments, the radar polygon, and viewport follow/zoom. Introduce a navigation-event adapter that supplies location, speed, maneuver distance, lanes, and current route geometry to the existing engine. Keep one owner for spoken turn guidance and one for camera alerts; never enable both SDK turn narration and custom turn narration at the same time. Compare road/direction confidence on the active route before speaking.

Changing the displayed map does not automatically change the route provider: route options currently come from the Worker, while active turn guidance comes from Google's Navigation SDK. A future Mapbox choice must make the route and navigation provider explicit and keep camera alerts independent of that choice.
