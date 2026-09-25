import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class PlacePhoto {
  const PlacePhoto({required this.name, required this.attribution});

  final String name;
  final String attribution;

  String get url =>
      Uri.parse('$workerBaseUrl/api/place-photo')
          .replace(queryParameters: {'name': name})
          .toString();

  factory PlacePhoto.fromJson(Map<String, dynamic> json) => PlacePhoto(
    name: json['name']?.toString() ?? '',
    attribution: json['attribution']?.toString() ?? '',
  );
}

class PlaceReview {
  const PlaceReview({
    required this.author,
    required this.authorPhoto,
    required this.rating,
    required this.text,
    required this.relativeTime,
    required this.googleMapsUri,
  });
  final String author;
  final String? authorPhoto;
  final double? rating;
  final String text;
  final String relativeTime;
  final String? googleMapsUri;

  factory PlaceReview.fromJson(Map<String, dynamic> json) => PlaceReview(
    author: json['author']?.toString() ?? 'Google user',
    authorPhoto: json['authorPhoto']?.toString(),
    rating: (json['rating'] as num?)?.toDouble(),
    text: json['text']?.toString() ?? '',
    relativeTime: json['relativeTime']?.toString() ?? '',
    googleMapsUri: json['googleMapsUri']?.toString(),
  );
}

class PlaceDetails {
  const PlaceDetails({
    required this.placeId,
    required this.name,
    required this.address,
    required this.primaryType,
    required this.rating,
    required this.userRatingCount,
    required this.businessStatus,
    required this.priceLevel,
    required this.phone,
    required this.websiteUri,
    required this.googleMapsUri,
    required this.editorialSummary,
    required this.openingHours,
    required this.photos,
    required this.reviews,
  });

  final String placeId;
  final String name;
  final String address;
  final String primaryType;
  final double? rating;
  final int? userRatingCount;
  final String? businessStatus;
  final String? priceLevel;
  final String phone;
  final String websiteUri;
  final String googleMapsUri;
  final String editorialSummary;
  final List<String> openingHours;
  final List<PlacePhoto> photos;
  final List<PlaceReview> reviews;

  factory PlaceDetails.fromJson(Map<String, dynamic> json) {
    final photos = (json['photos'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PlacePhoto.fromJson)
        .where((photo) => photo.name.isNotEmpty)
        .toList(growable: false);
    final reviews = (json['reviews'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PlaceReview.fromJson)
        .toList(growable: false);
    return PlaceDetails(
      placeId: json['placeId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Selected place',
      address: json['address']?.toString() ?? '',
      primaryType: json['primaryType']?.toString() ?? '',
      rating: (json['rating'] as num?)?.toDouble(),
      userRatingCount: (json['userRatingCount'] as num?)?.round(),
      businessStatus: json['businessStatus']?.toString(),
      priceLevel: json['priceLevel']?.toString(),
      phone: json['phone']?.toString() ?? '',
      websiteUri: json['websiteUri']?.toString() ?? '',
      googleMapsUri: json['googleMapsUri']?.toString() ?? '',
      editorialSummary: json['editorialSummary']?.toString() ?? '',
      openingHours: (json['openingHours'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      photos: photos,
      reviews: reviews,
    );
  }
}

class PlaceDetailsRepository {
  PlaceDetailsRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<PlaceDetails> fetch(String placeId, {String language = 'en'}) async {
    final uri = Uri.parse('$workerBaseUrl/api/place-details')
        .replace(queryParameters: {'placeId': placeId, 'lang': language});
    final response = await _client.get(uri);
    final decoded = jsonDecode(response.body);
    if (response.statusCode != 200 || decoded is! Map<String, dynamic>) {
      final message = decoded is Map<String, dynamic>
          ? decoded['error']?.toString()
          : null;
      throw StateError(message ?? 'Place details unavailable');
    }
    return PlaceDetails.fromJson(decoded);
  }

  void dispose() => _client.close();
}
