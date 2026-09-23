import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:http/http.dart' as http;

import '../data/api_config.dart';

class DestinationSuggestion {
  const DestinationSuggestion({required this.label, required this.location});
  final String label;
  final LatLng location;
}

class ExploreSearch extends StatefulWidget {
  const ExploreSearch({
    super.key,
    required this.currentLocation,
    required this.onSelected,
  });

  final LatLng? currentLocation;
  final ValueChanged<DestinationSuggestion> onSelected;

  @override
  State<ExploreSearch> createState() => _ExploreSearchState();
}

class _ExploreSearchState extends State<ExploreSearch> {
  final _controller = TextEditingController();
  final _client = http.Client();
  Timer? _debounce;
  bool _suggestConfigured = true;
  List<DestinationSuggestion> _results = const [];
  String? _error;
  int _request = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _client.close();
    super.dispose();
  }

  void _search(String text) {
    _debounce?.cancel();
    final request = ++_request;
    final query = text.trim();
    if (query.length < 3) {
      setState(() { _results = const []; _error = null; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 420), () async {
      try {
        final near = widget.currentLocation;
        final uri = Uri.parse('$workerBaseUrl/api/suggest').replace(queryParameters: {
          'q': query,
          'lang': 'en',
          if (near != null) 'near': '${near.longitude},${near.latitude}',
        });
        var response = await _client.get(_suggestConfigured
            ? uri
            : Uri.parse('$workerBaseUrl/api/search').replace(queryParameters: {'q': query}));
        if (_suggestConfigured && response.statusCode == 503) {
          _suggestConfigured = false;
          response = await _client.get(Uri.parse('$workerBaseUrl/api/search')
              .replace(queryParameters: {'q': query}));
        }
        if (response.statusCode != 200) throw StateError('Address search unavailable');
        final decoded = jsonDecode(response.body) as List<dynamic>;
        final places = decoded.whereType<Map<String, dynamic>>().map((item) {
          final latitude = item['latitude'];
          final longitude = item['longitude'];
          if (latitude is! num || longitude is! num) return null;
          return DestinationSuggestion(
            label: item['label']?.toString() ?? 'Selected destination',
            location: LatLng(latitude: latitude.toDouble(), longitude: longitude.toDouble()),
          );
        }).whereType<DestinationSuggestion>().toList();
        if (!mounted || request != _request) return;
        setState(() { _results = places; _error = null; });
      } catch (_) {
        if (!mounted || request != _request) return;
        setState(() { _results = const []; _error = 'Address search is unavailable'; });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.currentLocation;
    final locationText = location == null
        ? 'Locating current position…'
        : '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
    return Material(
      color: Colors.white,
      elevation: 11,
      borderRadius: BorderRadius.circular(21),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.my_location_rounded, size: 19, color: Color(0xFF295747)),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Current location', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                Text(locationText, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF788780), fontSize: 11)),
              ])),
            ]),
            const Divider(height: 19),
            Row(children: [
              const Icon(Icons.crop_square_rounded, size: 19, color: Color(0xFF9ACF45)),
              const SizedBox(width: 11),
              Expanded(child: TextField(
                controller: _controller,
                onChanged: _search,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Search destination',
                  hintStyle: TextStyle(color: Color(0xFF8A968E)),
                ),
              )),
              const Icon(Icons.search_rounded, color: Color(0xFF285747)),
            ]),
          ]),
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFB64B3A), fontSize: 12))),
        if (_results.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _results.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final result = _results[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined, color: Color(0xFF527C60)),
                  title: Text(result.label, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                  onTap: () {
                    _debounce?.cancel();
                    _request++;
                    _controller.text = result.label;
                    FocusScope.of(context).unfocus();
                    setState(() => _results = const []);
                    widget.onSelected(result);
                  },
                );
              },
            ),
          ),
      ]),
    );
  }
}
