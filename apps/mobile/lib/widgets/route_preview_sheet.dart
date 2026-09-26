import '../theme/tasman_theme.dart';

import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../domain/route_option.dart';
import '../data/parking_repository.dart';

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
    this.parkingPlaces = const [],
    this.selectedParkingId,
    this.finalDestinationTitle,
    this.parkingLoading = false,
    this.onParkingSelected,
    this.onDirectDestination,
    this.isChinese = false,
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
  final List<ParkingPlace> parkingPlaces;
  final String? selectedParkingId;
  final String? finalDestinationTitle;
  final bool parkingLoading;
  final ValueChanged<ParkingPlace>? onParkingSelected;
  final VoidCallback? onDirectDestination;
  final bool isChinese;

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
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxSheetHeight = (screenHeight * .44).clamp(330.0, 420.0);

    return PointerInterceptor(
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 0,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxSheetHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
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
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        tooltip: isFavorite
                            ? 'Remove favorite'
                            : 'Save favorite',
                        onPressed: onFavorite,
                        icon: Icon(
                          isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: isFavorite
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        tooltip: 'My review',
                        onPressed: onReview,
                        icon: const Icon(Icons.rate_review_outlined),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 1, 2, 5),
                    child: Row(
                      children: [
                        Icon(
                          Icons.my_location_rounded,
                          size: 14,
                          color: Theme.of(context).colorScheme.primary,
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
                  if (finalDestinationTitle != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          isChinese
                              ? '前往 $finalDestinationTitle · 停车点'
                              : 'Parking for $finalDestinationTitle',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      for (final mode in KiwiTravelMode.values)
                        Expanded(
                          child: InkWell(
                            onTap:
                                plan.forMode(mode).isEmpty ||
                                    (selectedParkingId != null &&
                                        mode != KiwiTravelMode.drive)
                                ? null
                                : () => onModeChanged(mode),
                            borderRadius: BorderRadius.circular(14),
                            child: Opacity(
                              opacity:
                                  plan.forMode(mode).isEmpty ||
                                      (selectedParkingId != null &&
                                          mode != KiwiTravelMode.drive)
                                  ? .35
                                  : 1,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: selectedMode == mode
                                      ? Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      _icon(mode),
                                      color: selectedMode == mode
                                          ? Theme.of(context)
                                                .colorScheme
                                                .onPrimaryContainer
                                          : Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                      size: 18,
                                    ),
                                    const SizedBox(height: 2),
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
                    const Divider(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        isChinese ? '路线选项' : 'Route options',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    for (var index = 0; index < routes.length; index++) ...[
                      _RouteOptionTile(
                        route: routes[index],
                        active: routes[index].id == selected?.id,
                        fastestDuration: fastestDuration,
                        onTap: () => onRouteSelected(routes[index]),
                      ),
                      if (index != routes.length - 1) const SizedBox(height: 6),
                    ],
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            routeExplanation(selected, routes).isNotEmpty
                                ? routeExplanation(selected, routes)
                                : 'Route preview',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 11,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.speed_rounded, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                '$cameraCount',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (selectedMode == KiwiTravelMode.drive)
                      _ParkingChoices(
                        places: parkingPlaces,
                        selectedId: selectedParkingId,
                        finalDestinationTitle:
                            finalDestinationTitle ?? destinationTitle,
                        loading: parkingLoading,
                        onSelected: onParkingSelected,
                        onDirect: onDirectDestination,
                        isChinese: isChinese,
                      ),
                    if (customOrigin)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Custom origin is for route preview; live guidance starts from your GPS.',
                          maxLines: 2,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.tertiary,
                            fontSize: 10,
                            height: 1.2,
                          ),
                        ),
                      ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 8,
                              ),
                            ),
                            onPressed: selectedMode == KiwiTravelMode.transit
                                ? null
                                : onAddStop,
                            icon: const Icon(
                              Icons.add_location_alt_outlined,
                              size: 16,
                            ),
                            label: Text(
                              stopCount == 0 ? 'Add stop' : 'Stops $stopCount',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 8,
                              ),
                            ),
                            onPressed: onSave,
                            icon: const Icon(
                              Icons.bookmark_border_rounded,
                              size: 16,
                            ),
                            label: const Text('Save', maxLines: 1),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: busy ? null : onStart,
                            style: FilledButton.styleFrom(
                              backgroundColor: TasmanColors.ocean,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 8,
                              ),
                            ),
                            icon: busy
                                ? const SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.navigation_rounded,
                                    size: 16,
                                  ),
                            label: Text(
                              busy
                                  ? 'Starting…'
                                  : selectedMode == KiwiTravelMode.transit
                                  ? 'Start trip'
                                  : 'Start',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
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

class _RouteOptionTile extends StatelessWidget {
  const _RouteOptionTile({
    required this.route,
    required this.active,
    required this.fastestDuration,
    required this.onTap,
  });

  final RouteOption route;
  final bool active;
  final int fastestDuration;
  final VoidCallback onTap;

  String get _trafficLabel {
    if (route.traffic.trafficJam > 0) return 'Heavier traffic';
    if (route.traffic.slow > 0) return 'Some traffic';
    return 'Light traffic';
  }

  Color _trafficColor() {
    if (route.traffic.trafficJam > 0) return TasmanColors.danger;
    if (route.traffic.slow > 0) return TasmanColors.warning;
    return TasmanColors.ocean;
  }

  List<Color> _trafficBars() {
    if (route.traffic.trafficJam > 0) {
      return const [
        TasmanColors.ocean,
        TasmanColors.warning,
        TasmanColors.warning,
        TasmanColors.danger,
        TasmanColors.danger,
      ];
    }
    if (route.traffic.slow > 0) {
      return const [
        TasmanColors.ocean,
        TasmanColors.ocean,
        TasmanColors.ocean,
        TasmanColors.warning,
        TasmanColors.warning,
      ];
    }
    return const [
      TasmanColors.ocean,
      TasmanColors.ocean,
      TasmanColors.ocean,
      TasmanColors.ocean,
      TasmanColors.ocean,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fastest = route.durationSeconds == fastestDuration;
    final delay = route.trafficDelaySeconds;
    final description = route.description.trim().isNotEmpty
        ? route.description.trim()
        : fastest
        ? 'Best route'
        : 'Alternative';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: active
              ? scheme.primaryContainer.withValues(alpha: .72)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? scheme.primary : theme.dividerColor,
            width: active ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: active ? scheme.primary : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _icon(route.mode),
                size: 17,
                color: active ? scheme.onPrimary : scheme.primary,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _duration(route.durationSeconds),
                    style: TextStyle(
                      color: active ? scheme.primary : scheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${_distance(route.distanceMeters)} · $description'
                    '${delay != null && delay > 60 ? ' · ${_duration(delay)} traffic' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 84,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _trafficLabel,
                    style: TextStyle(
                      color: _trafficColor(),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (final color in _trafficBars()) ...[
                        Container(
                          width: 10,
                          height: 4,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 2),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
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
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.tertiary.withValues(alpha: .35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              route.warnings.isNotEmpty
                  ? '$text · ${route.warnings.first}'
                  : text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onTertiaryContainer,
              ),
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
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
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
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 10,
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

class _ParkingChoices extends StatelessWidget {
  const _ParkingChoices({
    required this.places,
    required this.selectedId,
    required this.finalDestinationTitle,
    required this.loading,
    required this.onSelected,
    required this.onDirect,
    required this.isChinese,
  });

  final List<ParkingPlace> places;
  final String? selectedId;
  final String finalDestinationTitle;
  final bool loading;
  final ValueChanged<ParkingPlace>? onSelected;
  final VoidCallback? onDirect;
  final bool isChinese;

  String _walkDistance(double metres) => metres >= 1000
      ? '${(metres / 1000).toStringAsFixed(1)} km'
      : '${metres.round()} m';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.local_parking_rounded,
                  color: scheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isChinese ? '附近停车' : 'Nearby parking',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            isChinese
                ? '$finalDestinationTitle · 先驾车停车，再步行至终点'
                : '$finalDestinationTitle · Drive, park, then continue on foot',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
          ),
          if (onDirect != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onDirect,
                icon: const Icon(Icons.route_rounded, size: 17),
                label: Text(
                  isChinese ? '直接前往终点' : 'Route straight to destination',
                ),
              ),
            ),
          if (!loading && places.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                isChinese ? '附近暂无停车数据。' : 'No nearby parking data found.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          if (places.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: places.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final place = places[index];
                  final active = selectedId == place.id;
                  return InkWell(
                    onTap: () => onSelected?.call(place),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 200,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: active
                            ? scheme.primaryContainer
                            : scheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: active
                              ? scheme.primary
                              : scheme.outlineVariant,
                          width: active ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            place.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isChinese
                                ? '距终点 ${_walkDistance(place.distanceMeters)} · ${place.source}'
                                : '${_walkDistance(place.distanceMeters)} from destination · ${place.source}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                          if (place.address.isNotEmpty)
                            Text(
                              place.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          const Spacer(),
                          Text(
                            place.totalSpaces == null
                                ? (isChinese ? '选择停车点' : 'Select parking')
                                : isChinese
                                ? '总车位 ${place.totalSpaces}'
                                      '${place.mobilitySpaces == null ? '' : ' · 无障碍 ${place.mobilitySpaces}'}'
                                : '${place.totalSpaces} total spaces'
                                      '${place.mobilitySpaces == null ? '' : ' · ${place.mobilitySpaces} accessible'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
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
        ],
      ),
    );
  }
}

class ParkingContinuationCard extends StatelessWidget {
  const ParkingContinuationCard({
    super.key,
    required this.destinationTitle,
    required this.parkingTitle,
    required this.onContinue,
    required this.onEnd,
    this.isChinese = false,
  });

  final String destinationTitle;
  final String parkingTitle;
  final VoidCallback onContinue;
  final VoidCallback onEnd;
  final bool isChinese;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PointerInterceptor(
      child: Material(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_parking_rounded, color: scheme.primary),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        isChinese ? '驾车路段已结束' : 'Driving leg ended',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '$parkingTitle → $destinationTitle',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onEnd,
                        child: Text(isChinese ? '结束行程' : 'End trip'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: onContinue,
                        icon: const Icon(Icons.directions_walk_rounded),
                        label: Text(isChinese ? '继续步行' : 'Continue on foot'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
