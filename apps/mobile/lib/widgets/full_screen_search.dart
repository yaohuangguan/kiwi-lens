import '../theme/tasman_theme.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import '../providers/provider_contracts.dart';

class FullScreenSearch extends StatefulWidget {
  const FullScreenSearch({
    super.key,
    required this.provider,
    required this.resolve,
    required this.language,
    required this.recent,
    this.currentLocation,
    this.initialQuery = '',
    this.onDriveMode,
  });

  final SearchProvider provider;
  final Future<PlaceSummary> Function(PlaceCandidate) resolve;
  final String language;
  final List<PlaceSummary> recent;
  final GeoPoint? currentLocation;
  final String initialQuery;
  final VoidCallback? onDriveMode;

  @override
  State<FullScreenSearch> createState() => _FullScreenSearchState();
}

class _FullScreenSearchState extends State<FullScreenSearch> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  Timer? _debounce;
  int _request = 0;
  bool _loading = false;
  bool _resolving = false;
  String? _error;
  List<PlaceCandidate> _results = const [];

  String _text(String en, String zh) => widget.language == 'zh' ? zh : en;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search(widget.initialQuery);
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String input) {
    _debounce?.cancel();
    final request = ++_request;
    final query = input.trim();
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final results = await widget.provider.search(
          query,
          proximity: widget.currentLocation,
          language: widget.language,
        );
        if (!mounted || request != _request) return;
        setState(() {
          _results = results;
          _loading = false;
        });
      } catch (_) {
        if (!mounted || request != _request) return;
        setState(() {
          _results = const [];
          _loading = false;
          _error = _text('Search is temporarily unavailable', '搜索暂不可用');
        });
      }
    });
  }

  Future<void> _choose(PlaceCandidate candidate) async {
    if (_resolving) return;
    setState(() => _resolving = true);
    try {
      final place = await widget.resolve(candidate);
      if (!mounted) return;
      Navigator.of(context).pop(place);
    } catch (_) {
      if (mounted) {
        setState(() {
          _resolving = false;
          _error = _text('Could not open this place', '无法打开此地点');
        });
      }
    }
  }

  String _distance(GeoPoint? point) {
    final from = widget.currentLocation;
    if (point == null || from == null) return '';
    final metres = distanceMeters(
      from.latitude,
      from.longitude,
      point.latitude,
      point.longitude,
    );
    return metres < 1000
        ? '${metres.round()} m'
        : '${(metres / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final recent = _controller.text.trim().isEmpty;
    final items = recent
        ? widget.recent
              .map(
                (place) => PlaceCandidate(
                  name: place.name,
                  address: place.address,
                  category: place.category,
                  kind: place.kind,
                  location: place.location,
                  reference: place.reference,
                ),
              )
              .toList(growable: false)
        : _results;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        titleSpacing: 0,
        title: Material(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(22),
          child: TextField(
            controller: _controller,
            autofocus: true,
            enableSuggestions: true,
            autocorrect: false,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(
                  color: TasmanColors.sky,
                  width: 1.3,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(
                  color: TasmanColors.sky,
                  width: 1.3,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(
                  color: TasmanColors.ocean,
                  width: 1.8,
                ),
              ),
              hintText: _text('Where to?', '去哪儿？'),
            ),
            onChanged: _search,
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              onPressed: () {
                _controller.clear();
                _search('');
              },
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loading || _resolving)
            const LinearProgressIndicator(minHeight: 2),
          if (recent && items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 8),
              child: Text(
                _text('Recent', '最近搜索'),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          if (recent && widget.onDriveMode != null)
            ListTile(
              leading: const Icon(Icons.directions_car_filled_rounded),
              title: Text(_text('Just Drive', '自由驾驶')),
              subtitle: Text(
                _text(
                  'Safety camera alerts without a destination',
                  '无需目的地也可接收摄像头提醒',
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                widget.onDriveMode?.call();
              },
            ),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                final distance = _distance(item.location);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  leading: Icon(
                    item.kind == PlaceKind.address
                        ? Icons.signpost_outlined
                        : Icons.place_outlined,
                    color: scheme.primary,
                  ),
                  title: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: item.secondaryAddress.isEmpty
                      ? null
                      : Text(
                          item.secondaryAddress,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: distance.isEmpty
                      ? null
                      : Text(
                          distance,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                  onTap: () => _choose(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
