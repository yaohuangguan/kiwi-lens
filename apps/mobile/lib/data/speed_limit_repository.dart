import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class SpeedLimitInfo {
  const SpeedLimitInfo({required this.speedLimitKph, this.zoneName});

  final int? speedLimitKph;
  final String? zoneName;
}

class SpeedLimitRepository {
  SpeedLimitRepository({
    http.Client? client,
    this.baseUrl = workerBaseUrl,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<SpeedLimitInfo> fetch({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse('$baseUrl/api/speed-limit?at=$longitude,$latitude');
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw StateError('Speed limit API failed: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return SpeedLimitInfo(
      speedLimitKph: (body['speedLimitKph'] as num?)?.round(),
      zoneName: body['zoneName'] as String?,
    );
  }
}
