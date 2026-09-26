import '../theme/tasman_theme.dart';

import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../domain/route_option.dart';

const _ink = TasmanColors.darkOcean;
const _accent = TasmanColors.sky;

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

String routeExplanation(RouteOption selected, List<RouteOption> routes) {
  if (routes.isEmpty) return selected.description;
  final fastest = routes.reduce(
    (a, b) => a.durationSeconds <= b.durationSeconds ? a : b,
  );
  final facts = <String>[];
  final extra = selected.durationSeconds - fastest.durationSeconds;
  if (extra > 60) {
    facts.add('+${_duration(extra)} vs fastest');
  } else if (selected.mode == KiwiTravelMode.drive) {
    facts.add('Fastest available route');
  }
  final distanceDifference = selected.distanceMeters - fastest.distanceMeters;
  if (selected.id != fastest.id && distanceDifference.abs() >= 500) {
    facts.add(
      distanceDifference < 0
          ? '${_distance(-distanceDifference)} shorter'
          : '${_distance(distanceDifference)} longer',
    );
  }
  if ((selected.trafficDelaySeconds ?? 0) > 60) {
    facts.add('${_duration(selected.trafficDelaySeconds!)} traffic delay');
  }
  if (selected.description.isNotEmpty) facts.add(selected.description);
  return facts.join(' · ');
}

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
    required this.originTitle,
    required this.plan,
    required this.selectedMode,
    required this.selectedRouteId,
    required this.busy,
    required this.stopCount,
    required this.cameraCount,
    required this.customOrigin,
    required this.onModeChanged,
    required this.onRouteSelected,
    required this.onStart,
    required this.onAddStop,
    required this.onSave,
    required this.isFavorite,
    required this.onFavorite,
    required this.onReview,
    required this.onClose,
  });

  final String destinationTitle;
  final String originTitle;
  final RoutePlan plan;
  final KiwiTravelMode selectedMode;
  final String? selectedRouteId;
  final bool busy;
  final int stopCount;
  final int cameraCount;
  final bool customOrigin;
  final ValueChanged<KiwiTravelMode> onModeChanged;
  final ValueChanged<RouteOption> onRouteSelected;
  final VoidCallback onStart;
  final VoidCallback onAddStop;
  final VoidCallback onSave;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onReview;
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
    final fastestDuration = routes.isEmpty
        ? 0
        : routes
              .map((route) => route.durationSeconds)
              .reduce((a, b) => a < b ? a : b);

    return PointerInterceptor(
      child: Material(
        color: Colors.white,
        elevation: 22,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: TasmanColors.lightBorder,
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
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: isFavorite
                            ? 'Remove favorite'
                            : 'Save favorite',
                        onPressed: onFavorite,
                        icon: Icon(
                          isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: isFavorite ? Colors.redAccent : _ink,
                        ),
                      ),
                      IconButton(
                        tooltip: 'My review',
                        onPressed: onReview,
                        icon: const Icon(Icons.rate_review_outlined),
                      ),
                      IconButton(
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(3, 4, 3, 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.my_location_rounded,
                          size: 15,
                          color: Color(0xFF1479FF),
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            originTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 7),
                          child: Icon(Icons.arrow_forward_rounded, size: 15),
                        ),
                        Flexible(
                          child: Text(
                            destinationTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      for (final mode in KiwiTravelMode.values)
                        Expanded(
                          child: InkWell(
                            onTap: plan.forMode(mode).isEmpty
                                ? null
                                : () => onModeChanged(mode),
                            borderRadius: BorderRadius.circular(14),
                            child: Opacity(
                              opacity: plan.forMode(mode).isEmpty ? .35 : 1,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
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
                                      color: selectedMode == mode
                                          ? _ink
                                          : Colors.black54,
                                      size: 21,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      plan.forMode(mode).isEmpty
                                          ? '—'
                                          : _duration(
                                              plan
                                                  .forMode(mode)
                                                  .first
                                                  .durationSeconds,
                                            ),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
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
                      height: 94,
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
                              width: 182,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
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
                                    route.durationSeconds == fastestDuration
                                        ? 'Fastest'
                                        : 'Alternative',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: TasmanColors.deepTeal,
                                    ),
                                  ),
                                  Text(
                                    _duration(route.durationSeconds),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    '${_distance(route.distanceMeters)}'
                                    '${route.durationSeconds > fastestDuration + 60 ? ' · +${_duration(route.durationSeconds - fastestDuration)}' : ''}'
                                    '${delay != null && delay > 60 ? ' · ${_duration(delay)} traffic' : ''}',
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
                    if (selected.mode == KiwiTravelMode.drive &&
                        (selected.traffic.hasIssues ||
                            selected.warnings.isNotEmpty))
                      _TrafficCard(route: selected),
                    if (selected.mode == KiwiTravelMode.transit &&
                        selected.transit.isNotEmpty)
                      _TransitDetails(route: selected),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            routeExplanation(selected, routes).isNotEmpty
                                ? routeExplanation(selected, routes)
                                : 'Route preview',
                            style: const TextStyle(
                              color: Color(0xFF5D6C64),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Chip(
                        avatar: const Icon(Icons.speed_rounded, size: 18),
                        label: Text('$cameraCount cameras on selected route'),
                        backgroundColor: const Color(0xFFF0F7E1),
                      ),
                    ),
                    if (customOrigin)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Custom origin is for route preview; live guidance starts from your GPS.',
                          style: TextStyle(
                            color: Color(0xFF795D22),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: selectedMode == KiwiTravelMode.transit
                              ? null
                              : onAddStop,
                          icon: const Icon(Icons.add_location_alt_outlined),
                          label: Text(
                            stopCount == 0 ? 'Add stop' : 'Stops $stopCount',
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: onSave,
                          icon: const Icon(Icons.bookmark_border_rounded),
                          label: const Text('Save'),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: busy ? null : onStart,
                          style: FilledButton.styleFrom(
                            backgroundColor: _ink,
                            foregroundColor: _accent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 13,
                            ),
                          ),
                          icon: busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.navigation_rounded),
                          label: Text(
                            busy
                                ? 'Starting…'
                                : selectedMode == KiwiTravelMode.transit
                                ? 'Start trip'
                                : 'Start',
                          ),
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
    );
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({required this.route});

  final RouteOption route;

  @override
  Widget build(BuildContext context) {
    final jam = route.traffic.trafficJam;
    final slow = route.traffic.slow;
    final text = jam > 0
        ? '$jam heavy-traffic section${jam == 1 ? '' : 's'} ahead'
        : '$slow slow section${slow == 1 ? '' : 's'} ahead';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1C37A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFF9A5A13)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              route.warnings.isNotEmpty
                  ? '$text · ${route.warnings.first}'
                  : text,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransitDetails extends StatelessWidget {
  const _TransitDetails({required this.route});

  final RouteOption route;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (var index = 0; index < route.transit.length; index++) ...[
            if (index > 0) const Divider(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.directions_transit_rounded, size: 20),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          route.transit[index].lineName,
                          route.transit[index].headsign,
                        ].where((value) => value.isNotEmpty).join(' → '),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${route.transit[index].departureStop} → '
                        '${route.transit[index].arrivalStop}'
                        '${route.transit[index].stopCount > 0 ? ' · ${route.transit[index].stopCount} stops' : ''}',
                        style: const TextStyle(
                          color: Color(0xFF657169),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
