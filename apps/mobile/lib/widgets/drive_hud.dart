import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../drive/drive_engine.dart';

class DriveHud extends StatelessWidget {
  const DriveHud({super.key, required this.engine, required this.onStop});

  final DriveEngine engine;
  final VoidCallback onStop;

  String _formatDistance(double? meters) {
    if (meters == null) return '—';
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }

  String _laneSymbol(LaneShape shape) {
    return switch (shape) {
      LaneShape.normalLeft => '←',
      LaneShape.normalRight => '→',
      LaneShape.sharpLeft => '↙',
      LaneShape.sharpRight => '↘',
      LaneShape.slightLeft => '↖',
      LaneShape.slightRight => '↗',
      LaneShape.straight => '↑',
      LaneShape.uTurnLeft => '↶',
      LaneShape.uTurnRight => '↷',
      _ => '·',
    };
  }

  @override
  Widget build(BuildContext context) {
    final nav = engine.navInfo;
    final step = nav?.currentStep;
    final camera = engine.upcomingCamera;
    final cameraDistance = engine.upcomingCameraDistanceMeters;
    final speeding =
        engine.speedSeverity == SpeedAlertSeverity.minor ||
        engine.speedSeverity == SpeedAlertSeverity.major ||
        (engine.speedLimitKph != null &&
            engine.speedKph > engine.speedLimitKph!);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          children: [
            if (step != null)
              PointerInterceptor(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                  decoration: BoxDecoration(
                    color: const Color(0xF20B1717),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.navigation_rounded,
                        color: Color(0xFFC8F169),
                        size: 34,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatDistance(
                                nav?.distanceToCurrentStepMeters?.toDouble(),
                              ),
                              style: const TextStyle(
                                color: Color(0xFFC8F169),
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              step.fullInstructions ??
                                  step.fullRoadName ??
                                  'Continue',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (step.lanes?.isNotEmpty ?? false) ...[
                              const SizedBox(height: 9),
                              Wrap(
                                spacing: 5,
                                children: step.lanes!.map((lane) {
                                  final recommended = lane.laneDirections.any(
                                    (direction) => direction.isRecommended,
                                  );
                                  final text = lane.laneDirections
                                      .map(
                                        (direction) =>
                                            _laneSymbol(direction.laneShape),
                                      )
                                      .toSet()
                                      .join();
                                  return Container(
                                    constraints: const BoxConstraints(
                                      minWidth: 31,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: recommended
                                          ? const Color(0xFFC8F169)
                                          : const Color(0xFF1D302A),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      text,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: recommended
                                            ? const Color(0xFF102219)
                                            : Colors.white70,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onStop,
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white70,
                        tooltip: 'End drive',
                      ),
                    ],
                  ),
                ),
              ),
            const Spacer(),
            if (camera != null && cameraDistance != null)
              PointerInterceptor(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: cameraDistance <= 150
                        ? const Color(0xFFF7D66D)
                        : const Color(0xFFF5F0D8),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 20,
                        color: Color(0x26000000),
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.speed_rounded,
                        color: Color(0xFF7B5610),
                        size: 30,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Safety camera · ${_formatDistance(cameraDistance)}',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${camera.type} · ${camera.location}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF705E2B),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            PointerInterceptor(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xF20B1717),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    _SpeedMetric(
                      speedKph: engine.speedKph,
                      speedLimitKph: engine.speedLimitKph,
                      warning: speeding,
                    ),
                    Container(width: 1, height: 34, color: Colors.white12),
                    _Metric(
                      label: 'CAMERA',
                      value: cameraDistance == null
                          ? '—'
                          : _formatDistance(cameraDistance),
                    ),
                    if (nav?.distanceToFinalDestinationMeters != null) ...[
                      Container(width: 1, height: 34, color: Colors.white12),
                      _Metric(
                        label: 'REMAIN',
                        value: _formatDistance(
                          nav!.distanceToFinalDestinationMeters!.toDouble(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedMetric extends StatelessWidget {
  const _SpeedMetric({
    required this.speedKph,
    required this.speedLimitKph,
    required this.warning,
  });

  final double speedKph;
  final int? speedLimitKph;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final accent = warning ? const Color(0xFFFF6868) : const Color(0xFFC8F169);

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: warning ? const Color(0xFFFF5757) : Colors.white24,
            width: warning ? 2.2 : 1,
          ),
          boxShadow: warning
              ? const [
                  BoxShadow(
                    color: Color(0x40FF5757),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'SPEED',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  speedKph.round().toString(),
                  style: TextStyle(
                    color: accent,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 3),
                const Padding(
                  padding: EdgeInsets.only(bottom: 2),
                  child: Text(
                    'km/h',
                    style: TextStyle(color: Colors.white54, fontSize: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              speedLimitKph == null ? 'LIMIT —' : 'LIMIT $speedLimitKph',
              style: TextStyle(
                color: warning ? accent : Colors.white60,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: .4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFFC8F169),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
