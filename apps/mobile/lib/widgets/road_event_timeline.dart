import 'package:flutter/material.dart';

import '../domain/road_event.dart';
import '../theme/tasman_theme.dart';

class RoadEventTimeline extends StatelessWidget {
  const RoadEventTimeline({
    super.key,
    required this.events,
    this.maneuverLabel,
    this.dark = true,
  });

  final List<RoadEvent> events;
  final String? maneuverLabel;
  final bool dark;

  String _distance(RoadEvent event) {
    final metres = event.distanceAlongRoute ?? event.distanceFromDriver;
    if (metres == null) return '';
    if (metres >= 1000) return '${(metres / 1000).toStringAsFixed(1)} km';
    return '${metres.round()} m';
  }

  String _label(RoadEvent event) => switch (event.type) {
    RoadEventType.safetyCamera => 'Camera',
    RoadEventType.speedLimitChange => 'Speed change',
    RoadEventType.temporarySpeedLimit => 'Temp. limit',
    RoadEventType.roadworks => 'Roadworks',
    RoadEventType.incident => 'Incident',
    RoadEventType.congestion => 'Traffic',
    RoadEventType.schoolZone => 'School zone',
    RoadEventType.sharpCurve => 'Sharp curve',
    RoadEventType.laneMerge => 'Merge',
    RoadEventType.laneEnd => 'Lane ends',
    RoadEventType.oneLaneBridge => 'One-lane bridge',
    RoadEventType.flooding => 'Flooding',
    RoadEventType.slip => 'Slip',
    RoadEventType.strongWind => 'Strong wind',
    RoadEventType.lowVisibility => 'Low visibility',
    RoadEventType.ice =>
      event.observation == RoadEventObservation.inferred
          ? 'Possible ice'
          : 'Ice warning',
    RoadEventType.roadClosure => 'Road closed',
  };

  IconData _icon(RoadEventType type) => switch (type) {
    RoadEventType.safetyCamera => Icons.speed_rounded,
    RoadEventType.speedLimitChange ||
    RoadEventType.temporarySpeedLimit => Icons.signpost_rounded,
    RoadEventType.roadworks => Icons.construction_rounded,
    RoadEventType.incident ||
    RoadEventType.roadClosure => Icons.warning_amber_rounded,
    RoadEventType.congestion => Icons.traffic_rounded,
    RoadEventType.schoolZone => Icons.school_rounded,
    RoadEventType.sharpCurve => Icons.turn_sharp_left_rounded,
    RoadEventType.laneMerge ||
    RoadEventType.laneEnd => Icons.merge_type_rounded,
    RoadEventType.oneLaneBridge => Icons.linear_scale_rounded,
    RoadEventType.flooding => Icons.water_rounded,
    RoadEventType.slip => Icons.landscape_rounded,
    RoadEventType.strongWind => Icons.air_rounded,
    RoadEventType.lowVisibility => Icons.visibility_off_rounded,
    RoadEventType.ice => Icons.ac_unit_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final visible = events.take(4).toList(growable: false);
    if (visible.isEmpty && maneuverLabel == null) {
      return const SizedBox.shrink();
    }
    final foreground = dark ? TasmanColors.darkText : TasmanColors.lightText;
    final muted = dark
        ? TasmanColors.darkTextSecondary
        : TasmanColors.lightTextSecondary;
    final surface = dark
        ? TasmanColors.darkOcean.withValues(alpha: .94)
        : TasmanColors.lightSurface.withValues(alpha: .96);
    final items = <Widget>[
      _TimelineNode(
        icon: Icons.navigation_rounded,
        label: 'Now',
        detail: maneuverLabel ?? 'Driving',
        color: TasmanColors.sky,
        foreground: foreground,
        muted: muted,
      ),
      for (final event in visible)
        _TimelineNode(
          icon: _icon(event.type),
          label: _label(event),
          detail: _distance(event),
          color: event.severity.index >= RoadEventSeverity.warning.index
              ? TasmanColors.warning
              : event.type == RoadEventType.safetyCamera
              ? TasmanColors.teal
              : TasmanColors.coastal,
          foreground: foreground,
          muted: muted,
        ),
    ];

    return Semantics(
      label: 'Upcoming road events',
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(
          horizontal: TasmanSpacing.x3,
          vertical: TasmanSpacing.x2,
        ),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(TasmanRadius.panel),
          border: Border.all(
            color: dark ? TasmanColors.darkBorder : TasmanColors.lightBorder,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [TasmanColors.ocean, TasmanColors.teal],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: TasmanSpacing.x2),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var index = 0; index < items.length; index++) ...[
                      if (index > 0)
                        Container(
                          width: 24,
                          height: 2,
                          color: dark
                              ? TasmanColors.darkBorder
                              : TasmanColors.lightBorder,
                        ),
                      items[index],
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

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({
    required this.icon,
    required this.label,
    required this.detail,
    required this.color,
    required this.foreground,
    required this.muted,
  });

  final IconData icon;
  final String label;
  final String detail;
  final Color color;
  final Color foreground;
  final Color muted;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 60, maxWidth: 112),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 29,
          height: 29,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: foreground,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (detail.isNotEmpty)
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted, fontSize: 10),
          ),
      ],
    ),
  );
}
