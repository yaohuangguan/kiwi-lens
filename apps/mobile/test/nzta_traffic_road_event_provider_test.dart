import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiwi_lens_mobile/data/nzta_traffic_road_event_provider.dart';
import 'package:kiwi_lens_mobile/domain/road_event.dart';

void main() {
  test('parses normalized NZTA road events from Worker response', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/road-events');
      return http.Response(
        jsonEncode({
          'syncStatus': 'live',
          'checkedAt': '2026-09-26T00:00:00Z',
          'events': [
            {
              'id': 'nzta:event:1',
              'type': 'roadworks',
              'location': {'latitude': -36.85, 'longitude': 174.76},
              'roadName': 'SH 1 Auckland',
              'severity': 'warning',
              'confidence': 0.95,
              'validFrom': '2026-09-25T00:00:00Z',
              'validUntil': '2026-09-27T00:00:00Z',
              'source': {
                'provider': 'NZTA Traffic and Travel',
                'country': 'NZ',
                'region': 'Auckland',
                'sourceId': '1',
                'updatedAt': '2026-09-25T23:00:00Z'
              },
              'metadata': {'description': 'Road works'}
            }
          ]
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final provider = NztaTrafficRoadEventProvider(
      client: client,
      baseUrl: 'https://example.test',
    );
    final events = await provider.load();
    expect(provider.lastSyncStatus, 'live');
    expect(events, hasLength(1));
    expect(events.single.type, RoadEventType.roadworks);
    expect(events.single.severity, RoadEventSeverity.warning);
    expect(events.single.source.region, 'Auckland');
  });
}
