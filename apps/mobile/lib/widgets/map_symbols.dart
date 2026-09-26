import '../theme/tasman_theme.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import '../domain/map_layer_settings.dart';
import '../domain/map_provider.dart';
import '../providers/location_marker_art.dart';

class MapSymbols {
  static final Map<CameraKind, ImageDescriptor> _normal = {};
  static final Map<CameraKind, ImageDescriptor> _route = {};
  static ImageDescriptor? car;
  static final Map<LocationMarkerStyle, ImageDescriptor> _location = {};
  static Future<void>? _registration;

  static ImageDescriptor? camera(CameraKind kind, {required bool onRoute}) =>
      (onRoute ? _route : _normal)[kind];

  static ImageDescriptor? location(LocationMarkerStyle style) =>
      _location[style];

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
    for (final style in LocationMarkerStyle.values) {
      if (style == LocationMarkerStyle.classic) continue;
      final bytes = await LocationMarkerArt.png(style);
      _location[style] = await registerBitmapImage(
        bitmap: bytes.buffer.asByteData(),
        imagePixelRatio: 2,
      );
    }
  }

  static Future<ImageDescriptor> _registerCamera(
    CameraKind kind, {
    required bool onRoute,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;
    final color = switch (kind) {
      CameraKind.spotSpeed => const Color(0xFF1670B9),
      CameraKind.averageSpeed => const Color(0xFF0891B2),
      CameraKind.redLight => const Color(0xFFC64539),
      CameraKind.dualRedLightSpeed => const Color(0xFFD97706),
      CameraKind.other => const Color(0xFF7250A1),
    };
    paint.color = onRoute ? TasmanColors.sky : Colors.white;
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
      case CameraKind.averageSpeed:
        paint.style = PaintingStyle.stroke;
        paint.strokeWidth = 4;
        canvas.drawCircle(const Offset(27, 35), 10, paint);
        canvas.drawCircle(const Offset(45, 35), 10, paint);
        canvas.drawLine(const Offset(27, 22), const Offset(45, 22), paint);
        canvas.drawLine(const Offset(27, 48), const Offset(45, 48), paint);
        paint.style = PaintingStyle.fill;
        break;
      case CameraKind.dualRedLightSpeed:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(25, 13, 22, 42),
            const Radius.circular(5),
          ),
          paint,
        );
        paint.color = color;
        canvas.drawCircle(const Offset(36, 24), 4, paint);
        canvas.drawCircle(const Offset(36, 36), 4, paint);
        canvas.drawCircle(const Offset(36, 48), 4, paint);
        paint.color = Colors.white;
        canvas.drawCircle(const Offset(51, 20), 8, paint);
        paint.color = color;
        canvas.drawCircle(const Offset(51, 20), 4, paint);
        break;
      case CameraKind.spotSpeed:
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
    paint.color = TasmanColors.deepOcean;
    canvas.drawCircle(const Offset(36, 36), 26, paint);
    paint.color = TasmanColors.sky;
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
    paint.color = TasmanColors.deepOcean;
    canvas.drawCircle(const Offset(25, 49), 4, paint);
    canvas.drawCircle(const Offset(47, 49), 4, paint);
    final image = await recorder.endRecording().toImage(72, 72);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return registerBitmapImage(bitmap: bytes!, imagePixelRatio: 2);
  }
}
