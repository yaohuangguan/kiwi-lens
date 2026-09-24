import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../domain/route_option.dart';

const _ink = Color(0xFF0B1717);
const _lime = Color(0xFFC8F169);

String _duration(int seconds) {
  final duration = Duration(seconds: seconds);
  if (duration.inHours >= 1) {
    final minutes = duration.inMinutes.remainder(60);
    return minutes == 0
        ? '${duration.inHours} hr'
        : '${duration.inHours} hr $minutes min';
  }
  return '${duration.inMinutes.clamp(1, 999)} min';
}

String _distance(int metres) => metres >= 1000
    ? '${(metres / 1000).toStringAsFixed(metres < 10000 ? 1 : 0)} km'
    : '$metres m';

IconData _icon(KiwiTravelMode mode) => switch (mode) {
  KiwiTravelMode.drive => Icons.directions_car_filled_rounded,
  KiwiTravelMode.transit => Icons.train_rounded,
  KiwiTravelMode.walk => Icons.directions_walk_rounded,
  KiwiTravelMode.bicycle => Icons.pedal_bike_rounded,
};

class RoutePreviewSheet extends StatelessWidget {
  const RoutePreviewSheet({
    super.key,
    required this.destinationTitle,
    required this.plan,
    required this.selectedMode,
    required this.selectedRouteId,
    required this.busy,
    required this.onModeChanged,
    required this.onRouteSelected,
    required this.onStart,
    required this.onClose,
  });

  final String destinationTitle;
  final RoutePlan plan;
  final KiwiTravelMode selectedMode;
  final String? selectedRouteId;
  final bool busy;
  final ValueChanged<KiwiTravelMode> onModeChanged;
  final ValueChanged<RouteOption> onRouteSelected;
  final VoidCallback onStart;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final routes = plan.forMode(selectedMode).toList(growable: false);
    RouteOption? selected;
    for (final route in routes) {
      if (route.id == selectedRouteId) {
        selected = route;
        break;
      }
    }
    selected ??= routes.isEmpty ? null : routes.first;

    return PointerInterceptor(
      child: Material(
        color: Colors.white,
        elevation: 22,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD0D8D2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        destinationTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded)),
                  ],
                ),
                Row(
                  children: [
                    for (final mode in KiwiTravelMode.values)
                      Expanded(
                        child: InkWell(
                          onTap: plan.forMode(mode).isEmpty ? null : () => onModeChanged(mode),
                          borderRadius: BorderRadius.circular(14),
                          child: Opacity(
                            opacity: plan.forMode(mode).isEmpty ? .35 : 1,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: selectedMode == mode
                                    ? const Color(0xFFEAF4EA)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    _icon(mode),
                                    color: selectedMode == mode ? _ink : Colors.black54,
                                    size: 21,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    plan.forMode(mode).isEmpty
                                        ? '—'
                                        : _duration(plan.forMode(mode).first.durationSeconds),
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (routes.isNotEmpty) ...[
                  const Divider(height: 20),
                  SizedBox(
                    height: 76,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: routes.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final route = routes[index];
                        final active = route.id == selected?.id;
                        final delay = route.trafficDelaySeconds;
                        return InkWell(
                          onTap: () => onRouteSelected(route),
                          borderRadius: BorderRadius.circular(15),
                          child: Container(
                            width: 170,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: active
                                  ? const Color(0xFFF0F7E1)
                                  : const Color(0xFFF5F7F5),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: active
                                    ? const Color(0xFF91B850)
                                    : const Color(0xFFE2E7E3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _duration(route.durationSeconds),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  '${_distance(route.distanceMeters)}'
                                  '${delay != null && delay > 60 ? ' · +${_duration(delay)} traffic' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF68756E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (selected != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          plan.trafficAvailable && selectedMode == KiwiTravelMode.drive
                              ? (selected.trafficDelaySeconds ?? 0) > 60
                                  ? 'Traffic-aware route · live conditions included'
                                  : 'Fastest route based on current traffic'
                              : selected.description.isNotEmpty
                                  ? selected.description
                                  : 'Route preview',
                          style: const TextStyle(
                            color: Color(0xFF5D6C64),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: busy || selectedMode != KiwiTravelMode.drive
                            ? null
                            : onStart,
                        style: FilledButton.styleFrom(
                          backgroundColor: _ink,
                          foregroundColor: _lime,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 13,
                          ),
                        ),
                        icon: busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.navigation_rounded),
                        label: Text(busy ? 'Starting…' : 'Start'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
