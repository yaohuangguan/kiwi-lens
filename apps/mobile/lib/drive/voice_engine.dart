import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceEngine {
  VoiceEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _initialized = false;
  String _language = 'en-NZ';

  Future<void> setLanguage(String language) async {
    _language = language == 'zh-CN' ? 'zh-CN' : 'en-NZ';
    if (_initialized) await _tts.setLanguage(_language);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1);
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _tts.setAudioAttributesForNavigation();
    }
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
    required String roadName,
    String? speedLimit,
  }) async {
    await initialize();
    final lower = cameraType.toLowerCase();
    final isRedLight = lower.contains('red light');
    final isAverage = lower.contains('average');
    final type = _language == 'zh-CN'
        ? isRedLight
              ? '红灯摄像头'
              : isAverage
              ? '区间测速摄像头'
              : '固定测速摄像头'
        : isRedLight
        ? 'Red-light safety camera'
        : isAverage
        ? 'Average-speed camera'
        : 'Fixed speed camera';
    final message = _language == 'zh-CN'
        ? '前方 $distanceMeters 米有$type，位于$roadName。请提前减速，遵守限速。'
        : '$type in $distanceMeters metres on $roadName. Slow down and observe the posted speed limit.';
    await _tts.stop();
    await _tts.speak(message);
  }

  Future<void> dispose() async {
    await _tts.stop();
  }
}
