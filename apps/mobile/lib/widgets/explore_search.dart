import '../theme/tasman_theme.dart';

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
    this.isPoi,
  });
  final String label;
  final LatLng location;
  final String? name;
  final String? address;
  final bool? isPoi;
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
    this.destinationOnly = false,
    this.autofocus = false,
    this.initialQuery,
    this.resultsMaxHeight = 260,
  });

  final LatLng? currentLocation;
  final ValueChanged<DestinationSuggestion> onSelected;
  final DestinationSuggestion? origin;
  final ValueChanged<DestinationSuggestion?>? onOriginSelected;
  final ValueChanged<bool>? onFocusChanged;
  final List<DestinationSuggestion> recent;
  final String language;
  final bool destinationOnly;
  final bool autofocus;
  final String? initialQuery;
  final double resultsMaxHeight;

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
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _controller.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search(initial, origin: false);
      });
    }
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
    _debounce = Timer(const Duration(milliseconds: 300), () async {
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
                isPoi: item['isPoi'] is bool ? item['isPoi'] as bool : null,
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

  void _clearDestination() {
    _debounce?.cancel();
    _request++;
    _controller.clear();
    setState(() {
      _results = const [];
      _error = null;
    });
    _destinationFocus.requestFocus();
  }

  void _clearOrigin() {
    _debounce?.cancel();
    _request++;
    _originController.clear();
    setState(() {
      _results = const [];
      _error = null;
    });
    widget.onOriginSelected?.call(null);
    _originFocus.requestFocus();
  }

  String _resultTitle(DestinationSuggestion result) {
    final address = result.address?.trim() ?? '';
    final name = result.name?.trim() ?? '';
    if (result.isPoi == false && address.isNotEmpty) return address;
    if (name.isNotEmpty) return name;
    return result.label;
  }

  String _resultAddress(DestinationSuggestion result) {
    final address = result.address?.trim() ?? '';
    final title = _resultTitle(result);
    if (address == title) return '';
    return address;
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
                if (!widget.destinationOnly)
                  Row(
                    children: [
                      const Icon(
                        Icons.my_location_rounded,
                        size: 19,
                        color: TasmanColors.deepOcean,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _originController,
                              focusNode: _originFocus,
                              onChanged: (value) {
                                setState(() {});
                                _search(value, origin: true);
                              },
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText: widget.origin?.label ?? locationText,
                                hintStyle: const TextStyle(
                                  color: Color(0xFF788780),
                                  fontSize: 12,
                                ),
                                suffixIconConstraints: const BoxConstraints(
                                  minWidth: 34,
                                  minHeight: 34,
                                ),
                                suffixIcon: _originController.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: _text('Clear', '清空'),
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          size: 18,
                                        ),
                                        onPressed: _clearOrigin,
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
                    ],
                  ),
                if (!widget.destinationOnly) const Divider(height: 19),
                Row(
                  children: [
                    Semantics(
                      label: _text('Destination', '目的地'),
                      child: Container(
                        key: const Key('destinationSearchIcon'),
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: TasmanColors.sky,
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
                              color: TasmanColors.deepOcean,
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
                        autofocus: widget.autofocus,
                        onChanged: (value) {
                          setState(() {});
                          _search(value, origin: false);
                        },
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: _text('Where to?', '想去哪？'),
                          hintStyle: const TextStyle(color: Color(0xFF8A968E)),
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          suffixIcon: _controller.text.isEmpty
                              ? const Icon(
                                  Icons.search_rounded,
                                  color: Color(0xFF285747),
                                )
                              : IconButton(
                                  key: const Key('destinationClearButton'),
                                  tooltip: _text('Clear', '清空'),
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 20,
                                  ),
                                  onPressed: _clearDestination,
                                ),
                        ),
                      ),
                    ),
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
              ((_destinationFocus.hasFocus || widget.destinationOnly) &&
                  _controller.text.isEmpty &&
                  widget.recent.isNotEmpty))
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.resultsMaxHeight),
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
                  final address = _resultAddress(result);
                  final distance = _distanceLabel(result);
                  final title = _resultTitle(result);
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
                      title,
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
                        _originController.text = title;
                      } else {
                        _controller.text = title;
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

class DestinationSearchPage extends StatelessWidget {
  const DestinationSearchPage({
    super.key,
    required this.currentLocation,
    required this.recent,
    required this.language,
    this.initialQuery,
    this.onDriveMode,
  });

  final LatLng? currentLocation;
  final List<DestinationSuggestion> recent;
  final String language;
  final String? initialQuery;
  final VoidCallback? onDriveMode;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F4),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5, right: 8),
                      child: Material(
                        color: Colors.white,
                        elevation: 4,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .backButtonTooltip,
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ExploreSearch(
                        currentLocation: currentLocation,
                        recent: recent,
                        language: language,
                        destinationOnly: true,
                        autofocus: true,
                        initialQuery: initialQuery,
                        resultsMaxHeight:
                            height - (onDriveMode == null ? 150 : 230),
                        onSelected: (selection) =>
                            Navigator.of(context).pop(selection),
                      ),
                    ),
                  ],
                ),
              ),
              if (onDriveMode != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ListTile(
                    tileColor: const Color(0xFFF0F6E8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    leading: const Icon(Icons.directions_car_filled_rounded),
                    title: const Text(
                      'Just Drive',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text('Camera alerts without a destination'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: onDriveMode,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
