import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import '../domain/map_layer_settings.dart';

class MapSymbols {
  static final Map<CameraKind, ImageDescriptor> _normal = {};
  static final Map<CameraKind, ImageDescriptor> _route = {};
  static ImageDescriptor? car;
  static Future<void>? _registration;

  static ImageDescriptor? camera(CameraKind kind, {required bool onRoute}) =>
      (onRoute ? _route : _normal)[kind];

  static Future<void> ensureRegistered() =>
      _registration ??= _registerAll().catchError((Object error) {
        _registration = null;
        throw error;
      });

  static Future<void> _registerAll() async {
    for (final kind in CameraKind.values) {
      _normal[kind] = await _registerCamera(kind, onRoute: false);
      _route[kind] = await _registerCamera(kind, onRoute: true);
    }
    car = await _registerCar();
  }

  static Future<ImageDescriptor> _registerCamera(
    CameraKind kind, {
    required bool onRoute,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;
    final color = switch (kind) {
      CameraKind.speed => const Color(0xFF163D34),
      CameraKind.redLight => const Color(0xFFC64539),
      CameraKind.lane => const Color(0xFF3268A4),
      CameraKind.other => const Color(0xFF7250A1),
    };
    paint.color = onRoute ? const Color(0xFFC8F169) : Colors.white;
    canvas.drawCircle(const Offset(36, 34), 32, paint);
    paint.color = color;
    canvas.drawCircle(const Offset(36, 34), onRoute ? 27 : 29, paint);
    paint.color = Colors.white;

    switch (kind) {
      case CameraKind.redLight:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(26, 14, 20, 41),
            const Radius.circular(5),
          ),
          paint,
        );
        paint.color = color;
        for (final y in [22.0, 34.0, 46.0]) {
          canvas.drawCircle(Offset(36, y), 4, paint);
        }
        break;
      case CameraKind.lane:
        paint.strokeWidth = 3.2;
        canvas.drawLine(const Offset(24, 50), const Offset(27, 18), paint);
        canvas.drawLine(const Offset(48, 50), const Offset(45, 18), paint);
        final path = Path()
          ..moveTo(36, 19)
          ..lineTo(27, 32)
          ..lineTo(33, 32)
          ..lineTo(33, 47)
          ..lineTo(39, 47)
          ..lineTo(39, 32)
          ..lineTo(45, 32)
          ..close();
        canvas.drawPath(path, paint);
        break;
      case CameraKind.speed:
      case CameraKind.other:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(18, 26, 36, 24),
            const Radius.circular(5),
          ),
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(23, 21, 13, 8),
            const Radius.circular(2),
          ),
          paint,
        );
        paint.color = color;
        canvas.drawCircle(const Offset(36, 38), 8, paint);
        paint.color = Colors.white;
        canvas.drawCircle(const Offset(36, 38), 5, paint);
        break;
    }
    final image = await recorder.endRecording().toImage(72, 72);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return registerBitmapImage(bitmap: bytes!, imagePixelRatio: 2);
  }

  static Future<ImageDescriptor> _registerCar() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;
    paint.color = Colors.white;
    canvas.drawCircle(const Offset(36, 36), 30, paint);
    paint.color = const Color(0xFF153B32);
    canvas.drawCircle(const Offset(36, 36), 26, paint);
    paint.color = const Color(0xFFC8F169);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(17, 29, 38, 19),
        const Radius.circular(5),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(24, 21, 24, 12),
        const Radius.circular(5),
      ),
      paint,
    );
    paint.color = const Color(0xFF153B32);
    canvas.drawCircle(const Offset(25, 49), 4, paint);
    canvas.drawCircle(const Offset(47, 49), 4, paint);
    final image = await recorder.endRecording().toImage(72, 72);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return registerBitmapImage(bitmap: bytes!, imagePixelRatio: 2);
  }
}
