import 'package:flutter_tts/flutter_tts.dart';

class VoiceEngine {
  VoiceEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await _tts.setLanguage('en-NZ');
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1);
    await _tts.setAudioAttributesForNavigation();
    _initialized = true;
  }

  Future<void> guidance(String message) async {
    if (message.trim().isEmpty) return;
    await initialize();
    await _tts.stop();
    await _tts.speak(message);
  }

  Future<void> cameraAlert({
    required int distanceMeters,
    required String cameraType,
    String? speedLimit,
  }) async {
    await initialize();
    final type = cameraType.toLowerCase().contains('red light')
        ? 'red light safety camera'
        : 'speed camera';
    final limit = speedLimit == null ? '' : ', speed limit $speedLimit';
    await _tts.stop();
    await _tts.speak(
      'Safety alert. $type in $distanceMeters metres$limit. Please check your speed.',
    );
  }

  Future<void> dispose() async {
    await _tts.stop();
  }
}
