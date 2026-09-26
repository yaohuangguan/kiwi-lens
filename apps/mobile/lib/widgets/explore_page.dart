import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import '../data/explore_repository.dart';
import '../domain/geo_math.dart';
import '../theme/tasman_theme.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({
    super.key,
    required this.currentLocation,
    required this.language,
  });

  final LatLng? currentLocation;
  final String language;

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  final ExploreRepository _repository = ExploreRepository();
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<ExplorePlace> _places = const [];
  String _category = 'for-you';
  bool _loading = false;
  String? _error;
  int _request = 0;

  bool get _isChinese => widget.language == 'zh';
  String _text(String english, String chinese) =>
      _isChinese ? chinese : english;

  static const _categories = <(String, String, String, IconData)>[
    ('for-you', 'For you', '推荐', Icons.auto_awesome_rounded),
    ('food', 'Food', '美食', Icons.restaurant_rounded),
    ('coffee', 'Coffee', '咖啡', Icons.coffee_rounded),
    ('activities', 'Things to do', '玩乐', Icons.local_activity_rounded),
    ('shopping', 'Shopping', '购物', Icons.shopping_bag_rounded),
    ('parks', 'Parks', '公园', Icons.park_rounded),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ExplorePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentLocation == null && widget.currentLocation != null) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _repository.dispose();
    super.dispose();
  }

  void _searchChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    final query = value.trim();
    if (query.length == 1) return;
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_load(query: query));
    });
  }

  Future<void> _load({String? query}) async {
    final location = widget.currentLocation;
    if (location == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _text('Waiting for your location…', '正在获取你的位置…');
        });
      }
      return;
    }
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final places = await _repository.fetch(
        latitude: location.latitude,
        longitude: location.longitude,
        category: _category,
        language: widget.language,
        query: query ?? _search.text,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _places = places;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = _text(
          'Could not load nearby places. Pull to retry.',
          '附近地点加载失败，下拉重试。',
        );
      });
    }
  }

  void _selectCategory(String value) {
    if (_category == value && _search.text.isEmpty) return;
    _debounce?.cancel();
    _search.clear();
    setState(() => _category = value);
    unawaited(_load(query: ''));
  }

  String _distance(ExplorePlace place) {
    final current = widget.currentLocation;
    if (current == null) return '';
    final metres = distanceMeters(
      current.latitude,
      current.longitude,
      place.latitude,
      place.longitude,
    );
    if (metres < 1000) return '${metres.round()} m';
    final km = metres / 1000;
    final value = km < 10 ? km.toStringAsFixed(1) : km.round().toString();
    return '$value km';
  }

  String _priceLabel(String? priceLevel) {
    return switch (priceLevel) {
      'PRICE_LEVEL_INEXPENSIVE' => r'$',
      'PRICE_LEVEL_MODERATE' => r'$$',
      'PRICE_LEVEL_EXPENSIVE' => r'$$$',
      'PRICE_LEVEL_VERY_EXPENSIVE' => r'$$$$',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        title: Text(
          _text('Explore', '探索'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text('Discover something nearby', '看看附近有什么好玩的'),
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _text(
                        'Popular places around your current location',
                        '根据当前位置自动推荐热门地点',
                      ),
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: _search,
                      onChanged: _searchChanged,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: _text(
                          'Search restaurants, museums, activities…',
                          '搜索餐厅、博物馆、玩乐地点…',
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: scheme.primary,
                        ),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: _text('Clear', '清空'),
                                onPressed: () {
                                  _debounce?.cancel();
                                  _search.clear();
                                  setState(() {});
                                  unawaited(_load(query: ''));
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                        filled: true,
                        fillColor: scheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: theme.dividerColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: theme.dividerColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(
                            color: scheme.primary,
                            width: 1.6,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 39,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _categories.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 7),
                        itemBuilder: (context, index) {
                          final item = _categories[index];
                          return ChoiceChip(
                            avatar: Icon(item.$4, size: 17),
                            label: Text(_text(item.$2, item.$3)),
                            selected: _category == item.$1,
                            onSelected: (_) => _selectCategory(item.$1),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: LinearProgressIndicator(),
                ),
              ),
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ),
              ),
            if (!_loading && _error == null && _places.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Center(
                    child: Text(
                      _text('No nearby places found.', '附近暂时没有找到合适地点。'),
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
              sliver: SliverList.separated(
                itemCount: _places.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final place = _places[index];
                  return _ExploreCard(
                    place: place,
                    distance: _distance(place),
                    price: _priceLabel(place.priceLevel),
                    language: widget.language,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExploreCard extends StatelessWidget {
  const _ExploreCard({
    required this.place,
    required this.distance,
    required this.price,
    required this.language,
  });
  final ExplorePlace place;
  final String distance;
  final String price;
  final String language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final photo = place.photoUrl;
    final rating = place.rating;
    final isChinese = language == 'zh';
    return Material(
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(place),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (photo != null)
              SizedBox(
                height: 172,
                width: double.infinity,
                child: Image.network(
                  photo,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _PhotoFallback(),
                ),
              )
            else
              const SizedBox(
                height: 116,
                width: double.infinity,
                child: _PhotoFallback(),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 13, 15, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (rating != null)
                        Text(
                          '${rating.toStringAsFixed(1)} ★',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      if (place.userRatingCount != null)
                        Text('(${place.userRatingCount})'),
                      if (place.primaryType.isNotEmpty) Text(place.primaryType),
                      if (price.isNotEmpty) Text(price),
                      if (distance.isNotEmpty)
                        Text(
                          distance,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      if (place.openNow != null)
                        Text(
                          place.openNow!
                              ? (isChinese ? '营业中' : 'Open now')
                              : (isChinese ? '已关闭' : 'Closed'),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: place.openNow!
                                ? TasmanColors.success
                                : scheme.error,
                          ),
                        ),
                    ],
                  ),
                  if (place.address.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      place.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.surfaceContainerHighest],
        ),
      ),
      child: Center(
        child: Icon(Icons.explore_rounded, size: 42, color: scheme.primary),
      ),
    );
  }
}
