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

class TransitTripOverlay extends StatelessWidget {
  const TransitTripOverlay({
    super.key,
    required this.destinationTitle,
    required this.route,
    required this.gpsAccuracy,
    required this.onEnd,
    required this.onRecenter,
  });

  final String destinationTitle;
  final RouteOption route;
  final double? gpsAccuracy;
  final VoidCallback onEnd;
  final VoidCallback onRecenter;

  @override
  Widget build(BuildContext context) {
    final arrival = TimeOfDay.fromDateTime(
      DateTime.now().add(Duration(seconds: route.durationSeconds)),
    ).format(context);

    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          Positioned(
            top: 10,
            left: 14,
            right: 14,
            child: PointerInterceptor(
              child: Material(
                color: _ink,
                elevation: 12,
                borderRadius: BorderRadius.circular(22),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_transit_rounded, color: _lime, size: 34),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('TRANSIT TRIP',
                                style: TextStyle(color: _lime, fontSize: 11, fontWeight: FontWeight.w900)),
                            Text(destinationTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onRecenter,
                        tooltip: 'Recenter',
                        icon: const Icon(Icons.my_location_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: PointerInterceptor(
              child: Material(
                color: Colors.white,
                elevation: 18,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(27)),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_duration(route.durationSeconds),
                                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                                  Text('${_distance(route.distanceMeters)} · arrive $arrival · GPS ${gpsAccuracy == null ? '—' : '±${gpsAccuracy!.round()} m'}',
                                      style: const TextStyle(color: Color(0xFF6D7A73), fontSize: 11)),
                                ],
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: onEnd,
                              style: FilledButton.styleFrom(backgroundColor: _lime, foregroundColor: _ink),
                              icon: const Icon(Icons.stop_rounded),
                              label: const Text('End trip'),
                            ),
                          ],
                        ),
                        if (route.transit.isNotEmpty) ...[
                          const Divider(height: 22),
                          SizedBox(
                            height: 92,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: route.transit.length,
                              separatorBuilder: (_, _) => const Icon(Icons.chevron_right_rounded),
                              itemBuilder: (context, index) {
                                final leg = route.transit[index];
                                return Container(
                                  width: 190,
                                  padding: const EdgeInsets.all(11),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF2F4F8),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text([leg.lineName, leg.headsign].where((v) => v.isNotEmpty).join(' → '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w900)),
                                      const SizedBox(height: 4),
                                      Text('${leg.departureStop} → ${leg.arrivalStop}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF67736D))),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
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
