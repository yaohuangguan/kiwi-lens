import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:http/http.dart' as http;

import '../data/api_config.dart';
import '../domain/geo_math.dart';

class DestinationSuggestion {
  const DestinationSuggestion({
    required this.label,
    required this.location,
    this.name,
    this.address,
  });
  final String label;
  final LatLng location;
  final String? name;
  final String? address;
}

class ExploreSearch extends StatefulWidget {
  const ExploreSearch({
    super.key,
    required this.currentLocation,
    required this.onSelected,
    this.origin,
    this.onOriginSelected,
    this.onFocusChanged,
    this.recent = const [],
    this.language = 'en',
  });

  final LatLng? currentLocation;
  final ValueChanged<DestinationSuggestion> onSelected;
  final DestinationSuggestion? origin;
  final ValueChanged<DestinationSuggestion?>? onOriginSelected;
  final ValueChanged<bool>? onFocusChanged;
  final List<DestinationSuggestion> recent;
  final String language;

  @override
  State<ExploreSearch> createState() => _ExploreSearchState();
}

class _ExploreSearchState extends State<ExploreSearch> {
  final _controller = TextEditingController();
  final _originController = TextEditingController();
  final _destinationFocus = FocusNode();
  final _originFocus = FocusNode();
  bool _editingOrigin = false;
  final _client = http.Client();
  Timer? _debounce;
  bool _suggestConfigured = true;
  List<DestinationSuggestion> _results = const [];
  String? _error;
  int _request = 0;
  String _locationLabel = 'Locating current position…';
  LatLng? _lastReverseLocation;
  bool _reverseLookupPending = false;

  bool get _isChinese => widget.language == 'zh';
  String _text(String english, String chinese) =>
      _isChinese ? chinese : english;

  String _distanceLabel(DestinationSuggestion result) {
    final current = widget.currentLocation;
    if (current == null) return '';
    final metres = distanceMeters(
      current.latitude,
      current.longitude,
      result.location.latitude,
      result.location.longitude,
    );
    if (metres < 1000) return '${metres.round()} m';
    final kilometres = metres / 1000;
    return kilometres < 10
        ? '${kilometres.toStringAsFixed(1)} km'
        : '${kilometres.round()} km';
  }

  @override
  void initState() {
    super.initState();
    _destinationFocus.addListener(_focusChanged);
    _originFocus.addListener(_focusChanged);
    unawaited(_refreshCurrentLocationLabel(widget.currentLocation));
  }

  @override
  void didUpdateWidget(covariant ExploreSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget.currentLocation;
    final previous = _lastReverseLocation;
    if (current == null) {
      if (_locationLabel != 'Locating current position…') {
        setState(() => _locationLabel = 'Locating current position…');
      }
      return;
    }
    final moved = previous == null
        ? double.infinity
        : distanceMeters(
            previous.latitude,
            previous.longitude,
            current.latitude,
            current.longitude,
          );
    if (moved >= 120) {
      unawaited(_refreshCurrentLocationLabel(current));
    }
  }

  void _focusChanged() {
    if (_originFocus.hasFocus) _editingOrigin = true;
    if (_destinationFocus.hasFocus) _editingOrigin = false;
    widget.onFocusChanged?.call(
      _originFocus.hasFocus || _destinationFocus.hasFocus,
    );
    if (mounted) setState(() {});
  }

  Future<void> _refreshCurrentLocationLabel(LatLng? location) async {
    if (location == null || _reverseLookupPending) return;
    _reverseLookupPending = true;
    _lastReverseLocation = location;
    try {
      final uri = Uri.parse('$workerBaseUrl/api/reverse').replace(
        queryParameters: {'at': '${location.longitude},${location.latitude}'},
      );
      final response = await _client.get(uri);
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(response.body);
      final label = decoded is Map<String, dynamic>
          ? decoded['label']?.toString().trim()
          : null;
      if (!mounted || label == null || label.isEmpty) return;
      setState(() => _locationLabel = label);
    } catch (_) {
      // Keep the last readable place if reverse lookup is temporarily unavailable.
    } finally {
      _reverseLookupPending = false;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _originController.dispose();
    _destinationFocus.dispose();
    _originFocus.dispose();
    _client.close();
    super.dispose();
  }

  void _search(String text, {required bool origin}) {
    _editingOrigin = origin;
    _debounce?.cancel();
    final request = ++_request;
    final query = text.trim();
    if (query.length < 3) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 420), () async {
      try {
        final near = widget.currentLocation;
        final uri = Uri.parse('$workerBaseUrl/api/suggest').replace(
          queryParameters: {
            'q': query,
            'lang': widget.language,
            if (near != null) 'near': '${near.longitude},${near.latitude}',
          },
        );
        var response = await _client.get(
          _suggestConfigured
              ? uri
              : Uri.parse('$workerBaseUrl/api/search').replace(
                  queryParameters: {'q': query, 'lang': widget.language},
                ),
        );
        if (_suggestConfigured && response.statusCode == 503) {
          _suggestConfigured = false;
          response = await _client.get(
            Uri.parse(
              '$workerBaseUrl/api/search',
            ).replace(queryParameters: {'q': query, 'lang': widget.language}),
          );
        }
        if (response.statusCode != 200) {
          throw StateError('Address search unavailable');
        }
        final decoded = jsonDecode(response.body) as List<dynamic>;
        final places = decoded
            .whereType<Map<String, dynamic>>()
            .map((item) {
              final latitude = item['latitude'];
              final longitude = item['longitude'];
              if (latitude is! num || longitude is! num) return null;
              final label =
                  item['label']?.toString() ??
                  _text('Selected destination', '所选目的地');
              return DestinationSuggestion(
                label: label,
                name: item['name']?.toString().trim().isNotEmpty == true
                    ? item['name'].toString().trim()
                    : label,
                address: item['address']?.toString().trim(),
                location: LatLng(
                  latitude: latitude.toDouble(),
                  longitude: longitude.toDouble(),
                ),
              );
            })
            .whereType<DestinationSuggestion>()
            .toList();
        if (!mounted || request != _request) return;
        setState(() {
          _results = places;
          _error = null;
        });
      } catch (_) {
        if (!mounted || request != _request) return;
        setState(() {
          _results = const [];
          _error = _text('Address search is unavailable', '地址搜索暂不可用');
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.currentLocation;
    final locationText = location == null
        ? _text('Locating current position…', '正在定位当前位置…')
        : _locationLabel;
    return Material(
      color: Colors.white,
      elevation: 11,
      borderRadius: BorderRadius.circular(21),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.my_location_rounded,
                      size: 19,
                      color: Color(0xFF295747),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _originController,
                            focusNode: _originFocus,
                            onChanged: (value) => _search(value, origin: true),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: widget.origin?.label ?? locationText,
                              hintStyle: const TextStyle(
                                color: Color(0xFF788780),
                                fontSize: 12,
                              ),
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.origin != null)
                      IconButton(
                        tooltip: 'Use current location',
                        icon: const Icon(Icons.close_rounded, size: 19),
                        onPressed: () {
                          _originController.clear();
                          widget.onOriginSelected?.call(null);
                        },
                      ),
                  ],
                ),
                const Divider(height: 19),
                Row(
                  children: [
                    Semantics(
                      label: _text('Destination', '目的地'),
                      child: Container(
                        key: const Key('destinationSearchIcon'),
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: const Color(0xFFC8F169),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFF477B36),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF153B32),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _destinationFocus,
                        onChanged: (value) => _search(value, origin: false),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: _text('Search destination', '搜索目的地'),
                          hintStyle: const TextStyle(color: Color(0xFF8A968E)),
                        ),
                      ),
                    ),
                    const Icon(Icons.search_rounded, color: Color(0xFF285747)),
                  ],
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFB64B3A), fontSize: 12),
              ),
            ),
          if (_results.isNotEmpty ||
              (_destinationFocus.hasFocus &&
                  _controller.text.isEmpty &&
                  widget.recent.isNotEmpty))
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _results.isNotEmpty
                    ? _results.length
                    : widget.recent.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final result = _results.isNotEmpty
                      ? _results[index]
                      : widget.recent[index];
                  final address = result.address?.trim() ?? '';
                  final distance = _distanceLabel(result);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    leading: const Icon(
                      Icons.place_outlined,
                      color: Color(0xFF527C60),
                    ),
                    title: Text(
                      result.name ?? result.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: address.isEmpty && distance.isEmpty
                        ? null
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (address.isNotEmpty)
                                Text(
                                  address,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (distance.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    distance,
                                    style: const TextStyle(
                                      color: Color(0xFF477B36),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                    onTap: () {
                      _debounce?.cancel();
                      _request++;
                      if (_editingOrigin) {
                        _originController.text = result.label;
                      } else {
                        _controller.text = result.label;
                      }
                      FocusScope.of(context).unfocus();
                      setState(() => _results = const []);
                      if (_editingOrigin) {
                        widget.onOriginSelected?.call(result);
                      } else {
                        widget.onSelected(result);
                      }
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
