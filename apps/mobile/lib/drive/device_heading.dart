import 'package:flutter/services.dart';

class DeviceHeading {
  static const _channel = EventChannel('kiwi_lens/device_heading');

  static Stream<double> get readings => _channel.receiveBroadcastStream().map((event) {
    if (event is! Map) throw const FormatException('Invalid heading event');
    final heading = event['heading'];
    if (heading is! num || !heading.isFinite || heading < 0 || heading >= 360) {
      throw const FormatException('Invalid heading value');
    }
    return heading.toDouble();
  });
}
