import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../drive/drive_engine.dart';

const _ink = Color(0xFF0B1717);
const _lime = Color(0xFFC8F169);

String _distance(num? metres) {
  if (metres == null) return '—';
  if (metres >= 1000) return '${(metres / 1000).toStringAsFixed(1)} km';
  return '${metres.round()} m';
}

IconData _maneuverIcon(Maneuver? maneuver) {
  final name = maneuver?.name.toLowerCase() ?? '';
  if (name.contains('uturn')) return Icons.u_turn_left_rounded;
  if (name.contains('right')) return Icons.turn_right_rounded;
  if (name.contains('left')) return Icons.turn_left_rounded;
  if (name.contains('roundabout')) return Icons.roundabout_right_rounded;
  return Icons.straight_rounded;
}

class NavigationOverlay extends StatefulWidget {
  const NavigationOverlay({
    super.key,
    required this.engine,
    required this.destinationTitle,
    required this.gpsAccuracy,
    required this.voiceEnabled,
    required this.lanesEnabled,
    required this.onEnd,
    required this.onRecenter,
    required this.onOverview,
    required this.northUp,
    required this.onCompassToggle,
    required this.onReport,
    required this.onSearchAlongRoute,
    required this.onDirections,
    required this.onShare,
    required this.onSettings,
    required this.onVoiceToggle,
    required this.onLanesToggle,
  });

  final DriveEngine engine;
  final String destinationTitle;
  final double? gpsAccuracy;
  final bool voiceEnabled;
  final bool lanesEnabled;
  final VoidCallback onEnd;
  final VoidCallback onRecenter;
  final VoidCallback onOverview;
  final bool northUp;
  final VoidCallback onCompassToggle;
  final VoidCallback onReport;
  final VoidCallback onSearchAlongRoute;
  final VoidCallback onDirections;
  final VoidCallback onShare;
  final VoidCallback onSettings;
  final VoidCallback onVoiceToggle;
  final VoidCallback onLanesToggle;

  @override
  State<NavigationOverlay> createState() => _NavigationOverlayState();
}

class _NavigationOverlayState extends State<NavigationOverlay> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final nav = widget.engine.navInfo;
    final step = nav?.currentStep;
    final camera = widget.engine.upcomingCamera;
    final cameraDistance = widget.engine.upcomingCameraDistanceMeters;
    final remainingSeconds = nav?.timeToFinalDestinationSeconds;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final arrival = remainingSeconds == null
        ? '—'
        : TimeOfDay.fromDateTime(
            DateTime.now().add(Duration(seconds: remainingSeconds)),
          ).format(context);
    final speeding =
        widget.engine.speedLimitKph != null &&
        widget.engine.speedKph > widget.engine.speedLimitKph!;

    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          Positioned(
            top: 10,
            left: 14,
            right: 14,
            child: PointerInterceptor(
              child: Container(
                padding: const EdgeInsets.fromLTRB(17, 15, 17, 15),
                decoration: BoxDecoration(
                  color: _ink,
                  borderRadius: BorderRadius.circular(23),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x36000000),
                      blurRadius: 18,
                      offset: Offset(0, 7),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(_maneuverIcon(step?.maneuver), color: _lime, size: 40),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _distance(nav?.distanceToCurrentStepMeters),
                            style: const TextStyle(
                              color: _lime,
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            step?.fullInstructions ??
                                step?.fullRoadName ??
                                'Continue on route',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(width: 1, height: 53, color: Colors.white30),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          arrival,
                          style: const TextStyle(
                            color: _lime,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _distance(nav?.distanceToFinalDestinationMeters),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.lanesEnabled && (step?.lanes?.isNotEmpty ?? false))
            Positioned(
              top: 113,
              left: 14,
              right: 98,
              child: PointerInterceptor(
                child: Material(
                  color: _ink,
                  borderRadius: BorderRadius.circular(17),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    child: Wrap(
                      spacing: 7,
                      runSpacing: 5,
                      children: [
                        const Text(
                          'LANES',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        for (final lane in step!.lanes!)
                          Container(
                            constraints: const BoxConstraints(minWidth: 38),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  lane.laneDirections.any(
                                    (direction) => direction.isRecommended,
                                  )
                                  ? _lime
                                  : const Color(0xFF30453B),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              lane.laneDirections
                                  .map((direction) {
                                    final name = direction.laneShape.name
                                        .toLowerCase();
                                    return name.contains('left')
                                        ? '←'
                                        : name.contains('right')
                                        ? '→'
                                        : '↑';
                                  })
                                  .toSet()
                                  .join(),
                              style: TextStyle(
                                color:
                                    lane.laneDirections.any(
                                      (direction) => direction.isRecommended,
                                    )
                                    ? _ink
                                    : Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 132,
            right: 15,
            child: PointerInterceptor(
              child: Column(
                children: [
                  _MapControl(
                    icon: widget.northUp
                        ? Icons.explore_rounded
                        : Icons.navigation_rounded,
                    tooltip: widget.northUp
                        ? 'North up · tap for follow view'
                        : 'Follow view · tap for north up',
                    onTap: widget.onCompassToggle,
                  ),
                  const SizedBox(height: 9),
                  _MapControl(
                    icon: Icons.my_location_rounded,
                    tooltip: 'Recenter',
                    onTap: widget.onRecenter,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 232,
            left: 15,
            child: PointerInterceptor(
              child: Container(
                width: 84,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: _ink,
                  border: Border.all(
                    color: speeding ? const Color(0xFFFF6767) : Colors.white,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33000000), blurRadius: 14),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${widget.engine.speedKph.round()}',
                          style: TextStyle(
                            color: speeding ? const Color(0xFFFF6767) : _lime,
                            fontWeight: FontWeight.w900,
                            fontSize: 27,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 5),
                          child: Text(
                            'km/h',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'LIMIT ${widget.engine.speedLimitKph ?? '—'}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (camera != null && cameraDistance != null)
            Positioned(
              left: 14,
              bottom: bottomInset + (expanded ? 370 : 231),
              child: PointerInterceptor(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 235),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(19),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x36000000),
                        blurRadius: 16,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircleAvatar(
                        backgroundColor: _ink,
                        child: Icon(Icons.speed_rounded, color: _lime),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Camera · ${_distance(cameraDistance)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              camera.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF68756E),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: PointerInterceptor(
              child: Material(
                color: Colors.white,
                elevation: 18,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(27),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 5, 16, bottomInset + 15),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        key: const Key('navigationSheetHandle'),
                        onTap: () => setState(() => expanded = !expanded),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Container(
                            width: 51,
                            height: 5,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD0D8D2),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.destinationTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: widget.onEnd,
                            style: FilledButton.styleFrom(
                              backgroundColor: _lime,
                              foregroundColor: _ink,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            icon: const Icon(Icons.stop_rounded, size: 18),
                            label: const Text('End navigation'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            _TripStat(
                              label: 'Cameras on route',
                              value: '${widget.engine.routeCameraCount}',
                            ),
                            _TripStat(
                              label: 'Distance',
                              value: _distance(
                                nav?.distanceToFinalDestinationMeters,
                              ),
                            ),
                            _TripStat(label: 'Arrival', value: arrival),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _Chip(
                            icon: widget.voiceEnabled
                                ? Icons.volume_up_rounded
                                : Icons.volume_off_rounded,
                            label: widget.voiceEnabled
                                ? 'Voice ✓'
                                : 'Voice off',
                            onTap: widget.onVoiceToggle,
                          ),
                          const SizedBox(width: 6),
                          _Chip(
                            icon: Icons.alt_route_rounded,
                            label: widget.lanesEnabled
                                ? 'Lanes ✓'
                                : 'Lanes off',
                            onTap: widget.onLanesToggle,
                          ),
                          const SizedBox(width: 6),
                          _Chip(
                            icon: Icons.gps_fixed_rounded,
                            label: widget.gpsAccuracy == null
                                ? 'GPS —'
                                : 'GPS ±${widget.gpsAccuracy!.round()} m',
                            onTap: widget.onRecenter,
                          ),
                        ],
                      ),
                      if (expanded) ...[
                        const SizedBox(height: 15),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Trip tools',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _ActionButton(
                              icon: Icons.add_a_photo_rounded,
                              label: 'Add a report',
                              onTap: widget.onReport,
                            ),
                            _ActionButton(
                              icon: Icons.share_rounded,
                              label: 'Share ETA snapshot',
                              onTap: widget.onShare,
                            ),
                            _ActionButton(
                              icon: Icons.search_rounded,
                              label: 'Search along route',
                              onTap: widget.onSearchAlongRoute,
                            ),
                            _ActionButton(
                              icon: Icons.route_rounded,
                              label: 'Preview route',
                              onTap: widget.onOverview,
                            ),
                            _ActionButton(
                              icon: Icons.list_alt_rounded,
                              label: 'Directions',
                              onTap: widget.onDirections,
                            ),
                            _ActionButton(
                              icon: Icons.settings_rounded,
                              label: 'Settings',
                              onTap: widget.onSettings,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripStat extends StatelessWidget {
  const _TripStat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF84928A), fontSize: 10),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: const Color(0xFFF0F4F0),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: _ink),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MapControl extends StatelessWidget {
  const _MapControl({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 5,
      borderRadius: BorderRadius.circular(18),
      child: IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        icon: Icon(icon, color: _ink),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: (MediaQuery.sizeOf(context).width - 48) / 2,
    child: Material(
      color: const Color(0xFFF0F4F0),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: _ink, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
