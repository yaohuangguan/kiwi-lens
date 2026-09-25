import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiwi_lens_mobile/domain/map_provider.dart';
import 'package:kiwi_lens_mobile/domain/route_option.dart';
import 'package:kiwi_lens_mobile/providers/mapbox_routing_provider.dart';
import 'package:kiwi_lens_mobile/providers/place_search_providers.dart';

void main() {
  test(
    'Mapbox suggestions retrieve into a neutral POI with street address',
    () async {
      final paths = <String>[];
      final provider = MapboxSearchProvider(
        'test-token',
        client: MockClient((request) async {
          paths.add(request.url.path);
          expect(request.url.queryParameters['access_token'], 'test-token');
          if (request.url.path.endsWith('/suggest')) {
            expect(request.url.queryParameters['country'], 'NZ');
            expect(request.url.queryParameters['language'], 'zh');
            return http.Response(
              jsonEncode({
                'suggestions': [
                  {
                    'mapbox_id': 'place-1',
                    'name': 'Cordis Auckland',
                    'full_address':
                        'Cordis Auckland, 83 Symonds Street, Grafton, Auckland',
                    'feature_type': 'poi',
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'features': [
                {
                  'geometry': {
                    'coordinates': [174.764, -36.856],
                  },
                  'properties': {
                    'name': 'Cordis Auckland',
                    'full_address':
                        'Cordis Auckland, 83 Symonds Street, Grafton, Auckland',
                    'feature_type': 'poi',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final suggestions = await provider.search(
        'Cordis',
        proximity: const GeoPoint(-36.85, 174.76),
        language: 'zh',
      );
      expect(
        suggestions.single.secondaryAddress,
        '83 Symonds Street, Grafton, Auckland',
      );
      final place = await provider.resolve(
        suggestions.single.reference!,
        language: 'zh',
      );
      expect(place.location, const GeoPoint(-36.856, 174.764));
      expect(place.reference!.provider, 'mapbox');
      expect(place.address, '83 Symonds Street, Grafton, Auckland');
      expect(paths, [
        '/search/searchbox/v1/suggest',
        '/search/searchbox/v1/retrieve/place-1',
      ]);
      provider.dispose();
    },
  );

  test(
    'Mapbox routes normalize geometry and maneuver coordinates',
    () async {
      final provider = MapboxRoutingProvider(
        'test-token',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'routes': [
                {
                  'duration': 720,
                  'distance': 4800,
                  'geometry': {
                    'coordinates': [
                      [174.76, -36.85],
                      [174.78, -36.86],
                    ],
                  },
                  'legs': [
                    {
                      'steps': [
                        {
                          'distance': 500,
                          'maneuver': {
                            'instruction': 'Turn right',
                            'location': [174.77, -36.855],
                          },
                        },
                      ],
                    },
                  ],
                },
              ],
            }),
            200,
          ),
        ),
      );

      final plan = await provider.route(
        origin: const GeoPoint(-36.85, 174.76),
        destination: const GeoPoint(-36.86, 174.78),
        language: 'en',
      );
      final drive = plan.forMode(KiwiTravelMode.drive).single;
      expect(plan.provider, 'mapbox');
      expect(plan.trafficAvailable, isFalse);
      expect(drive.points.last, const GeoPoint(-36.86, 174.78));
      expect(drive.steps.single.location, const GeoPoint(-36.855, 174.77));
      provider.dispose();
    },
  );
}
