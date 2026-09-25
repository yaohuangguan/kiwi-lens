import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/place_details_repository.dart';
import '../domain/coordinate_formatter.dart';
import '../domain/map_provider.dart';

class PlaceDetailsContent extends StatelessWidget {
  const PlaceDetailsContent({
    super.key,
    required this.selectedPlace,
    required this.details,
    required this.detailsLoading,
    required this.detailsError,
    required this.routeBusy,
    required this.isFavorite,
    required this.onClose,
    required this.onNavigate,
    required this.onFavorite,
    required this.onReview,
  });

  final PlaceSummary selectedPlace;
  final PlaceDetails? details;
  final bool detailsLoading;
  final String? detailsError;
  final bool routeBusy;
  final bool isFavorite;
  final VoidCallback onClose;
  final VoidCallback onNavigate;
  final VoidCallback onFavorite;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final place = details;
    final address = place?.address.isNotEmpty == true
        ? place!.address
        : selectedPlace.address.isNotEmpty
        ? selectedPlace.address
        : formatCoordinate(
            selectedPlace.location.latitude,
            selectedPlace.location.longitude,
          );
    return Material(
      color: Colors.white,
      elevation: 18,
      borderRadius: BorderRadius.circular(26),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (place?.photos.isNotEmpty == true)
                      _PhotoStrip(photos: place!.photos),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  place?.name ?? selectedPlace.name,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (place?.primaryType.isNotEmpty == true)
                                  Text(
                                    place!.primaryType.toUpperCase(),
                                    style: const TextStyle(
                                      color: Color(0xFF507060),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                const SizedBox(height: 5),
                                Text(
                                  address,
                                  style: const TextStyle(
                                    color: Color(0xFF68766F),
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: onClose,
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                    ),
                    if (detailsLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (detailsError != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 6,
                        ),
                        child: Text(
                          detailsError!,
                          style: const TextStyle(
                            color: Color(0xFF9B4B3D),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    if (place != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                        child: _DetailsBody(place: place),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: routeBusy ? null : onNavigate,
                      icon: routeBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.directions_rounded, size: 19),
                      label: Text(routeBusy ? 'Routing' : 'Directions'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onFavorite,
                    icon: Icon(
                      isFavorite
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_outline_rounded,
                    ),
                    label: const Text('Save'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text:
                              '${selectedPlace.name}\n$address\n'
                              '${selectedPlace.location.latitude},'
                              '${selectedPlace.location.longitude}',
                        ),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Place copied to clipboard'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share'),
                  ),
                  TextButton.icon(
                    onPressed: onReview,
                    icon: const Icon(Icons.more_horiz_rounded, size: 18),
                    label: const Text('More'),
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

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.photos});
  final List<PlacePhoto> photos;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 185,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 3),
        itemBuilder: (context, index) {
          final photo = photos[index];
          return SizedBox(
            width: MediaQuery.sizeOf(context).width * 0.78,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  photo.url,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const ColoredBox(
                          color: Color(0xFFE7ECE8),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Color(0xFFE7ECE8),
                    child: Center(
                      child: Icon(Icons.image_not_supported_outlined),
                    ),
                  ),
                ),
                if (photo.attribution.isNotEmpty)
                  Positioned(
                    left: 7,
                    right: 7,
                    bottom: 5,
                    child: Text(
                      '© ${photo.attribution}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        shadows: [Shadow(blurRadius: 5, color: Colors.black87)],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DetailsBody extends StatelessWidget {
  const _DetailsBody({required this.place});
  final PlaceDetails place;

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      if (place.businessStatus == 'OPERATIONAL') 'Open / operational',
      if (place.businessStatus != null && place.businessStatus != 'OPERATIONAL')
        place.businessStatus!.replaceAll('_', ' '),
      if (place.priceLevel != null) place.priceLevel!.replaceAll('_', ' '),
      if (place.phone.isNotEmpty) place.phone,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (place.rating != null)
          Row(
            children: [
              const Icon(
                Icons.star_rounded,
                color: Color(0xFFE0A11B),
                size: 20,
              ),
              const SizedBox(width: 4),
              Text(
                place.rating!.toStringAsFixed(1),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 6),
              Text(
                '${place.userRatingCount ?? 0} ratings',
                style: const TextStyle(color: Color(0xFF78857F), fontSize: 12),
              ),
            ],
          ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final chip in chips)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F5F1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(chip, style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ],
        if (place.editorialSummary.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            place.editorialSummary,
            style: const TextStyle(fontSize: 13, height: 1.45),
          ),
        ],
        if (place.openingHours.isNotEmpty) ...[
          const SizedBox(height: 10),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              'Opening hours',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            children: [
              for (final line in place.openingHours)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: Color(0xFF5E6D66),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (place.reviews.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                'Google reviews',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Text(
                '${place.reviews.length} shown',
                style: const TextStyle(color: Color(0xFF849089), fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final review in place.reviews) _ReviewTile(review: review),
        ],
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});
  final PlaceReview review;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFFE9EFEA),
            backgroundImage: review.authorPhoto?.isNotEmpty == true
                ? NetworkImage(review.authorPhoto!)
                : null,
            child: review.authorPhoto?.isNotEmpty == true
                ? null
                : const Icon(Icons.person_rounded, size: 17),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        review.author,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (review.rating != null)
                      Text(
                        '${review.rating!.toStringAsFixed(1)} ★',
                        style: const TextStyle(
                          color: Color(0xFF9A7115),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
                if (review.relativeTime.isNotEmpty)
                  Text(
                    review.relativeTime,
                    style: const TextStyle(
                      color: Color(0xFF8A948E),
                      fontSize: 9,
                    ),
                  ),
                if (review.text.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    review.text,
                    style: const TextStyle(
                      color: Color(0xFF52635B),
                      fontSize: 11,
                      height: 1.4,
                    ),
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
