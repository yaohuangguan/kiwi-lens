import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import '../providers/provider_contracts.dart';

abstract interface class DetourEstimator {
  Future<Duration?> estimate(PlaceSummary place, List<GeoPoint> route);
}

/// Placeholder until an extra routing request can measure the actual detour.
/// Returning null keeps the UI from presenting a misleading minute count.
class NoDetourEstimate implements DetourEstimator {
  const NoDetourEstimate();

  @override
  Future<Duration?> estimate(PlaceSummary place, List<GeoPoint> route) async =>
      null;
}

class ExploreSheet extends StatefulWidget {
  const ExploreSheet({
    super.key,
    required this.provider,
    required this.center,
    required this.language,
    required this.route,
    required this.saved,
    required this.markerFocus,
    required this.onResultsChanged,
    required this.onFocused,
    required this.onSelected,
    this.detourEstimator = const NoDetourEstimate(),
  });

  final ExploreProvider provider;
  final GeoPoint center;
  final String language;
  final List<GeoPoint> route;
  final List<PlaceSummary> saved;
  final ValueNotifier<PlaceSummary?> markerFocus;
  final ValueChanged<List<PlaceSummary>> onResultsChanged;
  final ValueChanged<PlaceSummary> onFocused;
  final ValueChanged<PlaceSummary> onSelected;
  final DetourEstimator detourEstimator;

  @override
  State<ExploreSheet> createState() => _ExploreSheetState();
}

class _ExploreSheetState extends State<ExploreSheet> {
  static const categories = [
    'Food',
    'Coffee',
    'Fuel',
    'Parking',
    'Public toilets',
    'EV charging',
    'Viewpoints',
    'Beaches',
    'Walks / trails',
    'Attractions',
  ];
  static const queries = {
    'Food': 'restaurant',
    'Coffee': 'coffee',
    'Fuel': 'gas station',
    'Parking': 'parking',
    'Public toilets': 'public toilet',
    'EV charging': 'EV charging station',
    'Viewpoints': 'viewpoint',
    'Beaches': 'beach',
    'Walks / trails': 'walking trail',
    'Attractions': 'attraction',
  };

  final PageController _cards = PageController(viewportFraction: 0.88);
  String _category = 'Food';
  List<PlaceSummary> _places = const [];
  bool _loading = false;
  String? _error;
  int _request = 0;

  String _text(String en, String zh) => widget.language == 'zh' ? zh : en;

  @override
  void initState() {
    super.initState();
    widget.markerFocus.addListener(_markerFocused);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void dispose() {
    widget.markerFocus.removeListener(_markerFocused);
    _cards.dispose();
    super.dispose();
  }

  void _markerFocused() {
    final target = widget.markerFocus.value;
    if (target == null) return;
    final index = _places.indexOf(target);
    if (index >= 0 && _cards.hasClients) {
      _cards.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final places = await widget.provider.nearby(
        queries[_category]!,
        center: widget.center,
        language: widget.language,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _places = places;
        _loading = false;
      });
      widget.onResultsChanged(places);
      if (places.isNotEmpty) widget.onFocused(places.first);
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _places = const [];
        _loading = false;
        _error = _text(
          'Nearby places are temporarily unavailable.',
          '附近地点暂不可用。',
        );
      });
      widget.onResultsChanged(const []);
    }
  }

  String _distance(PlaceSummary place) {
    final metres = distanceMeters(
      widget.center.latitude,
      widget.center.longitude,
      place.location.latitude,
      place.location.longitude,
    );
    return metres < 1000
        ? '${metres.round()} m'
        : '${(metres / 1000).toStringAsFixed(1)} km';
  }

  bool _nearRoute(PlaceSummary place) {
    if (widget.route.isEmpty) return false;
    return widget.route.any(
      (point) =>
          distanceMeters(
            point.latitude,
            point.longitude,
            place.location.latitude,
            place.location.longitude,
          ) <
          1500,
    );
  }

  @override
  Widget build(BuildContext context) {
    final alongRoute = _places.where(_nearRoute).toList(growable: false);
    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 34,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFB8C9D8),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 3, 18, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _text('Explore useful stops', '探索实用目的地'),
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _text(
                    'Nearby or along your journey in New Zealand',
                    '寻找附近或沿途的新西兰目的地',
                  ),
                  style: const TextStyle(color: Color(0xFF667C8E)),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 43,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (final category in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: Text(category),
                      selected: _category == category,
                      onSelected: (_) {
                        setState(() => _category = category);
                        unawaited(_load());
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(18), child: Text(_error!)),
          if (_places.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 17, 18, 10),
              child: Text(
                _text('Around you', '附近'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            SizedBox(
              height: 158,
              child: PageView.builder(
                controller: _cards,
                itemCount: _places.length,
                onPageChanged: (index) => widget.onFocused(_places[index]),
                itemBuilder: (context, index) {
                  final place = _places[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Card(
                      color: Colors.white,
                      child: InkWell(
                        onTap: () => widget.onSelected(place),
                        child: Padding(
                          padding: const EdgeInsets.all(17),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                place.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                place.address,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF61788C),
                                  fontSize: 12,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _distance(place),
                                style: const TextStyle(
                                  color: Color(0xFF1479FF),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
              children: [
                if (alongRoute.isNotEmpty) ...[
                  Text(
                    _text('Along your route', '沿途'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  for (final place in alongRoute.take(5))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(place.name),
                      subtitle: Text(
                        '${_distance(place)} · ${_text('near route', '靠近路线')}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => widget.onSelected(place),
                    ),
                  const SizedBox(height: 14),
                ],
                if (widget.saved.isNotEmpty) ...[
                  Text(
                    _text('Saved / frequent', '收藏与常去'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  for (final place in widget.saved.take(4))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(place.name),
                      subtitle: Text(place.address),
                      onTap: () => widget.onSelected(place),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
