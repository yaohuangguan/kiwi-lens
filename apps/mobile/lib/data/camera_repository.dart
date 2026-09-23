import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/safety_camera.dart';

class CameraRepository {
  CameraRepository({
    http.Client? client,
    this.baseUrl = 'https://kiwi-lens.nzs.workers.dev',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<List<SafetyCamera>> fetchCameras() async {
    final response = await _client.get(Uri.parse('$baseUrl/api/cameras'));
    if (response.statusCode != 200) {
      throw StateError('Camera API failed: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final cameras = body['cameras'] as List<dynamic>? ?? const [];
    return cameras
        .whereType<Map<String, dynamic>>()
        .map(SafetyCamera.fromJson)
        .toList(growable: false);
  }
}
