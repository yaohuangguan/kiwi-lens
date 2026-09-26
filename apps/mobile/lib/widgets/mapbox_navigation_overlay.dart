import 'package:flutter/material.dart';

import '../drive/drive_engine.dart';
import '../providers/mapbox_navigation_engine.dart';
import '../theme/tasman_theme.dart';
import 'road_event_timeline.dart';

class MapboxNavigationOverlay extends StatelessWidget {
  const MapboxNavigationOverlay({
    super.key,
    required this.engine,
    required this.drive,
    required this.destination,
    required this.language,
    required this.onEnd,
    required this.onRecenter,
  });

  final MapboxNavigationEngine engine;
  final DriveEngine drive;
  final String destination;
  final String language;
  final VoidCallback onEnd;
  final VoidCallback onRecenter;

  String _text(String en, String zh) => language == 'zh' ? zh : en;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([engine, drive]),
    builder: (context, _) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final dark = theme.brightness == Brightness.dark;
      final next = engine.nextStep;
      final distance = engine.distanceToStepMeters;
      final remaining = engine.remainingDistanceMeters;
      return SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 12,
              left: 14,
              right: 14,
              child: Material(
                color: TasmanColors.midnightOcean,
                elevation: 10,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        next == null
                            ? _text('Continue to destination', '继续前往目的地')
                            : distance >= 1000
                            ? '${(distance / 1000).toStringAsFixed(1)} km'
                            : '${distance.round()} m',
                        style: const TextStyle(
                          color: Color(0xFF8CC5FF),
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        next?.instruction ?? destination,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 120,
              child: FloatingActionButton.small(
                heroTag: 'mapbox-recenter',
                onPressed: onRecenter,
                child: const Icon(Icons.my_location_rounded),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Material(
                color: scheme.surface,
                elevation: 12,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(17),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${engine.remainingSeconds ~/ 60} min · '
                                  '${(remaining / 1000).toStringAsFixed(1)} km',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                                if (drive.upcomingCamera != null)
                                  Text(
                                    _text(
                                      'Safety camera ahead · '
                                          '${drive.upcomingCameraDistanceMeters?.round() ?? 0} m',
                                      '前方摄像头 · '
                                          '${drive.upcomingCameraDistanceMeters?.round() ?? 0} 米',
                                    ),
                                    style: TextStyle(
                                      color: scheme.error,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: onEnd,
                            child: Text(_text('End', '结束')),
                          ),
                        ],
                      ),
                      if (drive.upcomingRoadEvents.isNotEmpty) ...[
                        const SizedBox(height: TasmanSpacing.x2),
                        RoadEventTimeline(
                          events: drive.upcomingRoadEvents,
                          dark: dark,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
