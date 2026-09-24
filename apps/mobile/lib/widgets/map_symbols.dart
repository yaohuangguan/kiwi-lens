import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

class MapSymbols {
  static ImageDescriptor? camera;
  static ImageDescriptor? routeCamera;
  static ImageDescriptor? car;

  static Future<void> ensureRegistered() async {
    camera ??= await _registerCamera(const Color(0xFF153B32));
    routeCamera ??= await _registerCamera(const Color(0xFFC8F169));
    car ??= await _registerCar();
  }

  static Future<ImageDescriptor> _registerCamera(Color background) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;
    paint.color = Colors.white;
    canvas.drawCircle(const Offset(36, 34), 31, paint);
    paint.color = background;
    canvas.drawCircle(const Offset(36, 34), 27, paint);
    paint.color = background == const Color(0xFFC8F169)
        ? const Color(0xFF0B1717)
        : Colors.white;
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
    paint.color = background;
    canvas.drawCircle(const Offset(36, 38), 8, paint);
    paint.color = Colors.white;
    canvas.drawCircle(const Offset(36, 38), 5, paint);
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
