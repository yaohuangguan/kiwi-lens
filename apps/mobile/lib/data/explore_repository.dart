import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class ExplorePlace {
  const ExplorePlace({
    required this.placeId,
    required this.name,
    required this.address,
    required this.primaryType,
    required this.rating,
    required this.userRatingCount,
    required this.priceLevel,
    required this.openNow,
    required this.latitude,
    required this.longitude,
    required this.photoName,
    required this.photoAttribution,
  });

  final String placeId;
  final String name;
  final String address;
  final String primaryType;
  final double? rating;
  final int? userRatingCount;
  final String? priceLevel;
  final bool? openNow;
  final double latitude;
  final double longitude;
  final String photoName;
  final String photoAttribution;

  String? get photoUrl => photoName.isEmpty
      ? null
      : Uri.parse('$workerBaseUrl/api/place-photo')
            .replace(queryParameters: {'name': photoName})
            .toString();

  factory ExplorePlace.fromJson(Map<String, dynamic> json) => ExplorePlace(
    placeId: json['placeId']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Nearby place',
    address: json['address']?.toString() ?? '',
    primaryType: json['primaryType']?.toString() ?? '',
    rating: (json['rating'] as num?)?.toDouble(),
    userRatingCount: (json['userRatingCount'] as num?)?.round(),
    priceLevel: json['priceLevel']?.toString(),
    openNow: json['openNow'] as bool?,
    latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
    longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
    photoName: json['photoName']?.toString() ?? '',
    photoAttribution: json['photoAttribution']?.toString() ?? '',
  );
}

class ExploreRepository {
  ExploreRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<ExplorePlace>> fetch({
    required double latitude,
    required double longitude,
    required String category,
    required String language,
    String query = '',
  }) async {
    final uri = Uri.parse('$workerBaseUrl/api/explore').replace(
      queryParameters: {
        'at': '$longitude,$latitude',
        'category': category,
        'lang': language,
        if (query.trim().isNotEmpty) 'q': query.trim(),
      },
    );
    final response = await _client.get(uri);
    final decoded = jsonDecode(response.body);
    if (response.statusCode != 200 || decoded is! List<dynamic>) {
      final message = decoded is Map<String, dynamic>
          ? decoded['error']?.toString()
          : null;
      throw StateError(message ?? 'Explore places are unavailable');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(ExplorePlace.fromJson)
        .where(
          (place) =>
              place.placeId.isNotEmpty &&
              place.latitude != 0 &&
              place.longitude != 0,
        )
        .toList(growable: false);
  }

  void dispose() => _client.close();
}
