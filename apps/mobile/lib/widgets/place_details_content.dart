import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/place_details_repository.dart';
import '../domain/coordinate_formatter.dart';
import '../domain/map_provider.dart';
import '../theme/tasman_theme.dart';

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final place = details;
    final address = place?.address.isNotEmpty == true
        ? place!.address
        : selectedPlace.address.isNotEmpty
        ? selectedPlace.address
        : formatCoordinate(
            selectedPlace.location.latitude,
            selectedPlace.location.longitude,
          );
    final title = place?.name ?? selectedPlace.name;
    final type =
        (place?.primaryType.isNotEmpty == true
                ? place!.primaryType
                : selectedPlace.category)
            .replaceAll('_', ' ')
            .trim();

    return Material(
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: (MediaQuery.sizeOf(context).height * .66).clamp(
            430.0,
            620.0,
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (place?.photos.isNotEmpty == true)
                _PhotoStrip(photos: place!.photos)
              else
                _PhotoFallback(title: title),
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (type.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              type,
                              style: TextStyle(
                                color: scheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            address,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              if (place?.rating != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: TasmanColors.warning,
                            size: 17,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            place!.rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${place.userRatingCount ?? 0} ratings',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      if (place.businessStatus != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: scheme.outline,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              place.businessStatus == 'OPERATIONAL'
                                  ? 'Open / operational'
                                  : place.businessStatus!.replaceAll('_', ' '),
                              style: TextStyle(
                                color: place.businessStatus == 'OPERATIONAL'
                                    ? TasmanColors.success
                                    : scheme.onSurfaceVariant,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _PlaceAction(
                        icon: Icons.directions_car_filled_rounded,
                        label: routeBusy ? 'Routing' : 'Drive',
                        selected: true,
                        busy: routeBusy,
                        onTap: routeBusy ? null : onNavigate,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _PlaceAction(
                        icon: isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        label: 'Save',
                        selected: false,
                        onTap: onFavorite,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _PlaceAction(
                        icon: Icons.ios_share_rounded,
                        label: 'Share',
                        selected: false,
                        onTap: () async {
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
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _PlaceAction(
                        icon: Icons.more_horiz_rounded,
                        label: 'More',
                        selected: false,
                        onTap: onReview,
                      ),
                    ),
                  ],
                ),
              ),
              if (detailsLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (detailsError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                  child: Text(
                    detailsError!,
                    style: TextStyle(
                      color: scheme.error,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (place != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
                  child: _DetailsBody(place: place),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceAction extends StatelessWidget {
  const _PlaceAction({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected ? scheme.primary : scheme.surfaceContainerLow;
    final foreground = selected ? scheme.onPrimary : scheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(15),
          border: selected
              ? null
              : Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            else
              Icon(icon, color: foreground, size: 21),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: foreground,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
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
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 150,
      child: PageView.builder(
        itemCount: photos.length.clamp(1, 4),
        itemBuilder: (context, index) {
          final photo = photos[index];
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                photo.url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: scheme.primary,
                          ),
                        ),
                      ),
                errorBuilder: (_, _, _) => ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: .28),
                    ],
                  ),
                ),
              ),
              if (photo.attribution.isNotEmpty)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 6,
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
          );
        },
      ),
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 92,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.surfaceContainerHighest],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.place_rounded, color: scheme.primary, size: 34),
    );
  }
}

class _DetailsBody extends StatelessWidget {
  const _DetailsBody({required this.place});
  final PlaceDetails place;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chips = <String>[
      if (place.priceLevel != null) place.priceLevel!.replaceAll('_', ' '),
      if (place.phone.isNotEmpty) place.phone,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chips.isNotEmpty)
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
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Text(
                    chip,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        if (place.editorialSummary.isNotEmpty) ...[
          if (chips.isNotEmpty) const SizedBox(height: 12),
          Text(
            place.editorialSummary,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: scheme.onSurface,
            ),
          ),
        ],
        if (place.openingHours.isNotEmpty) ...[
          const SizedBox(height: 10),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            dense: true,
            shape: const Border(),
            collapsedShape: const Border(),
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
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (place.reviews.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Google reviews',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Text(
                '${place.reviews.length} shown',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 3),
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: scheme.surfaceContainerHighest,
            backgroundImage: review.authorPhoto?.isNotEmpty == true
                ? NetworkImage(review.authorPhoto!)
                : null,
            child: review.authorPhoto?.isNotEmpty == true
                ? null
                : Icon(
                    Icons.person_rounded,
                    size: 17,
                    color: scheme.onSurfaceVariant,
                  ),
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
                          color: TasmanColors.warning,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
                if (review.relativeTime.isNotEmpty)
                  Text(
                    review.relativeTime,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 9,
                    ),
                  ),
                if (review.text.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    review.text,
                    style: TextStyle(
                      color: scheme.onSurface,
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
