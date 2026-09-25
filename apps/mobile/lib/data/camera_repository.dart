import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/safety_camera.dart';
import 'api_config.dart';

class CameraSnapshot {
  const CameraSnapshot({
    required this.cameras,
    required this.syncStatus,
    this.sourceUpdatedAt,
    this.checkedAt,
  });

  final List<SafetyCamera> cameras;
  final String syncStatus;
  final DateTime? sourceUpdatedAt;
  final DateTime? checkedAt;
}

class CameraRepository {
  CameraRepository({http.Client? client, this.baseUrl = workerBaseUrl})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<CameraSnapshot> fetchSnapshot() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/api/cameras'))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('Camera API failed: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final cameras = (body['cameras'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SafetyCamera.fromJson)
        .toList(growable: false);
    return CameraSnapshot(
      cameras: cameras,
      syncStatus: body['syncStatus']?.toString() ?? 'unknown',
      sourceUpdatedAt: DateTime.tryParse(
        body['sourceUpdatedAt']?.toString() ?? '',
      ),
      checkedAt: DateTime.tryParse(body['checkedAt']?.toString() ?? ''),
    );
  }

  Future<List<SafetyCamera>> fetchCameras() async =>
      (await fetchSnapshot()).cameras;
}
