import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import 'explore_repository.dart';

const atParkingSource =
    'https://services2.arcgis.com/JkPEgZJGxhSjYOo0/arcgis/rest/services/ParkingService/FeatureServer/1';

class ParkingPlace {
  const ParkingPlace({
    required this.id,
    required this.name,
    required this.address,
    required this.location,
    required this.distanceMeters,
    required this.source,
    this.totalSpaces,
    this.mobilitySpaces,
    this.clearanceMeters,
    this.googlePlaceId,
  });

  final String id;
  final String name;
  final String address;
  final GeoPoint location;
  final double distanceMeters;
  final String source;
  final int? totalSpaces;
  final int? mobilitySpaces;
  final double? clearanceMeters;
  final String? googlePlaceId;

  PlaceSummary toPlaceSummary() => PlaceSummary(
    name: name,
    location: location,
    address: address,
    category: 'Parking',
    reference: googlePlaceId == null
        ? null
        : ProviderReference('google', googlePlaceId!),
  );
}

class ParkingRepository {
  ParkingRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<ParkingPlace>> nearby({
    required GeoPoint destination,
    required bool allowGoogleFallback,
    String language = 'en',
  }) async {
    try {
      final at = await _nearbyAt(destination);
      if (at.isNotEmpty || !allowGoogleFallback) return at;
    } catch (_) {
      if (!allowGoogleFallback) rethrow;
    }
    return _nearbyGoogle(destination, language);
  }

  Future<List<ParkingPlace>> _nearbyAt(GeoPoint destination) async {
    final uri = Uri.parse('$atParkingSource/query').replace(
      queryParameters: {
        'f': 'geojson',
        'where': "DATATYPE IN ('Covered Parking','Open Air Parking')",
        'geometry': '${destination.longitude},${destination.latitude}',
        'geometryType': 'esriGeometryPoint',
        'inSR': '4326',
        'spatialRel': 'esriSpatialRelIntersects',
        'distance': '1500',
        'units': 'esriSRUnit_Meter',
        'outFields': 'OBJECTID,DATATYPE,SHORTDESCRIPTION,LONGDESCRIPTION,STREETNUMBER,STREET,SUBURB,STATUS,TOTALSPACES,MOBILITYSPACES,CLEARANCEMETERS',
        'outSR': '4326',
        'returnGeometry': 'true',
        'resultRecordCount': '100',
      },
    );
    final response = await _client
        .get(uri, headers: {'accept': 'application/geo+json'})
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('AT parking HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> || data['features'] is! List) {
      throw const FormatException('Invalid AT parking response');
    }
    final places = <ParkingPlace>[];
    for (final raw in data['features'] as List) {
      if (raw is! Map<String, dynamic>) continue;
      final properties = raw['properties'];
      final geometry = raw['geometry'];
      if (properties is! Map<String, dynamic> ||
          geometry is! Map<String, dynamic>) {
        continue;
      }
      final coordinates = geometry['coordinates'];
      if (coordinates is! List ||
          coordinates.length < 2 ||
          coordinates[0] is! num ||
          coordinates[1] is! num) {
        continue;
      }
      final longitude = (coordinates[0] as num).toDouble();
      final latitude = (coordinates[1] as num).toDouble();
      final location = GeoPoint(latitude, longitude);
      final id = _nonnegativeInt(properties['OBJECTID']);
      if (!location.isValid ||
          id == null ||
          RegExp(
            'closed|inactive|removed',
            caseSensitive: false,
          ).hasMatch('${properties['STATUS'] ?? ''}')) {
        continue;
      }
      final distance = distanceMeters(
        destination.latitude,
        destination.longitude,
        latitude,
        longitude,
      );
      if (distance > 1500) continue;
      final address = [
        properties['STREETNUMBER'],
        properties['STREET'],
        properties['SUBURB'],
      ].where((part) => part != null && '$part'.trim().isNotEmpty).join(' ');
      final name = [
        properties['SHORTDESCRIPTION'],
        properties['LONGDESCRIPTION'],
        address,
        'AT car park',
      ].map((part) => '$part'.trim()).firstWhere((part) => part.isNotEmpty);
      final clearance = double.tryParse(
        '${properties['CLEARANCEMETERS'] ?? ''}',
      );
      places.add(
        ParkingPlace(
          id: 'at-$id',
          name: name,
          address: address,
          location: location,
          distanceMeters: distance,
          source: 'AT',
          totalSpaces: _nonnegativeInt(properties['TOTALSPACES']),
          mobilitySpaces: _nonnegativeInt(properties['MOBILITYSPACES']),
          clearanceMeters: clearance != null && clearance > 1 && clearance < 6
              ? clearance
              : null,
        ),
      );
    }
    places.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return places.take(8).toList(growable: false);
  }

  Future<List<ParkingPlace>> _nearbyGoogle(
    GeoPoint destination,
    String language,
  ) async {
    final places = await ExploreRepository(client: _client).fetch(
      latitude: destination.latitude,
      longitude: destination.longitude,
      category: 'parking',
      language: language,
    );
    final nearby = places
        .map((place) {
          final location = GeoPoint(place.latitude, place.longitude);
          return ParkingPlace(
            id: 'google-${place.placeId}',
            name: place.name,
            address: place.address,
            location: location,
            distanceMeters: distanceMeters(
              destination.latitude,
              destination.longitude,
              location.latitude,
              location.longitude,
            ),
            source: 'Google',
            googlePlaceId: place.placeId,
          );
        })
        .where((place) => place.distanceMeters <= 1500)
        .toList();
    nearby.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return nearby.take(8).toList(growable: false);
  }

  int? _nonnegativeInt(Object? value) {
    final result = int.tryParse('$value');
    return result != null && result >= 0 && result <= 10000 ? result : null;
  }

  void dispose() => _client.close();
}
