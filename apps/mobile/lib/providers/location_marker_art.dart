import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/map_provider.dart';

/// A small north-facing bird silhouette for the location puck. This is
/// separate from the Kiwi Lens logo; the existing logo remains unchanged.
class LocationMarkerArt {
  static final Map<LocationMarkerStyle, Future<Uint8List>> _cache = {};

  static Future<Uint8List> png(LocationMarkerStyle style) =>
      _cache.putIfAbsent(style, () => _draw(style));

  static Future<Uint8List> _draw(LocationMarkerStyle style) async {
    const size = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;
    paint.color = Colors.white;
    canvas.drawCircle(const Offset(48, 48), 43, paint);
    paint.color = const Color(0xFF0879E8);
    canvas.drawCircle(const Offset(48, 48), 38, paint);
    paint.color = Colors.white;

    switch (style) {
      case LocationMarkerStyle.kiwi:
        final body = Path()
          ..moveTo(47, 26)
          ..cubicTo(25, 29, 21, 58, 39, 68)
          ..cubicTo(54, 78, 73, 62, 69, 46)
          ..cubicTo(65, 34, 57, 27, 47, 26)
          ..close();
        canvas.drawPath(body, paint);
        final beak = Path()
          ..moveTo(48, 30)
          ..lineTo(48, 5)
          ..lineTo(54, 30)
          ..close();
        canvas.drawPath(beak, paint);
        paint.color = const Color(0xFF0A3769);
        canvas.drawCircle(const Offset(58, 38), 2.8, paint);
        paint.strokeWidth = 4;
        canvas.drawLine(const Offset(37, 68), const Offset(33, 76), paint);
        canvas.drawLine(const Offset(56, 68), const Offset(60, 76), paint);
      case LocationMarkerStyle.arrow:
        final arrow = Path()
          ..moveTo(48, 14)
          ..lineTo(67, 71)
          ..lineTo(48, 60)
          ..lineTo(29, 71)
          ..close();
        canvas.drawPath(arrow, paint);
      case LocationMarkerStyle.car:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(29, 22, 38, 52),
            const Radius.circular(10),
          ),
          paint,
        );
        paint.color = const Color(0xFF0A3769);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(34, 32, 28, 17),
            const Radius.circular(4),
          ),
          paint,
        );
      case LocationMarkerStyle.classic:
        canvas.drawCircle(const Offset(48, 48), 16, paint);
    }
    final image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }
}
