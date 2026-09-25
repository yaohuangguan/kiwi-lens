import 'package:flutter/material.dart';

import '../domain/map_layer_settings.dart';
import '../domain/map_provider.dart';

class MapLayerSheet extends StatefulWidget {
  const MapLayerSheet({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.mapProvider,
    required this.language,
  });
  final MapLayerSettings settings;
  final ValueChanged<MapLayerSettings> onChanged;
  final MapProvider mapProvider;
  final String language;

  @override
  State<MapLayerSheet> createState() => _MapLayerSheetState();
}

class _MapLayerSheetState extends State<MapLayerSheet> {
  late MapLayerSettings current = widget.settings;

  String _text(String en, String zh) => widget.language == 'zh' ? zh : en;

  void update(MapLayerSettings next) {
    setState(() => current = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(27)),
      child: SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          children: [
            Center(
              child: Container(
                width: 52,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD0D8D2),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _text('Map layers', '地图图层'),
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              _text(
                'Choose what appears on the map. Camera alerts remain available during an active trip.',
                '选择地图显示内容。行程中仍可接收安全摄像头提醒。',
              ),
              style: const TextStyle(color: Color(0xFF607269), fontSize: 12),
            ),
            const SizedBox(height: 15),
            SegmentedButton<BaseMapStyle>(
              segments: [
                ButtonSegment(
                  value: BaseMapStyle.standard,
                  icon: const Icon(Icons.map_outlined),
                  label: Text(_text('Map', '地图')),
                ),
                ButtonSegment(
                  value: BaseMapStyle.satellite,
                  icon: const Icon(Icons.satellite_alt_outlined),
                  label: Text(_text('Satellite', '卫星')),
                ),
                ButtonSegment(
                  value: BaseMapStyle.terrain,
                  icon: const Icon(Icons.terrain_outlined),
                  label: Text(_text('Terrain', '地形')),
                ),
              ],
              selected: {
                current.style == BaseMapStyle.hybrid
                    ? BaseMapStyle.satellite
                    : current.style,
              },
              onSelectionChanged: (value) =>
                  update(current.copyWith(style: value.first)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.traffic_rounded),
              title: Text(_text('Live traffic', '实时交通')),
              subtitle: Text(
                widget.mapProvider == MapProvider.google
                    ? _text(
                        'Google traffic colours on the base map',
                        'Google 地图底图显示交通颜色',
                      )
                    : _text(
                        'Not available on the Mapbox map in this build',
                        '此版本的 Mapbox 地图暂不支持',
                      ),
              ),
              value:
                  widget.mapProvider == MapProvider.google && current.traffic,
              onChanged: widget.mapProvider == MapProvider.google
                  ? (value) => update(current.copyWith(traffic: value))
                  : null,
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.photo_camera_rounded),
              title: Text(_text('Safety cameras', '安全摄像头')),
              value: current.cameras,
              onChanged: (value) => update(current.copyWith(cameras: value)),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(_text('Speed', '测速')),
                    value: current.speed,
                    onChanged: current.cameras
                        ? (value) => update(current.copyWith(speed: value))
                        : null,
                  ),
                  SwitchListTile(
                    title: Text(_text('Red light', '闯红灯')),
                    value: current.redLight,
                    onChanged: current.cameras
                        ? (value) => update(current.copyWith(redLight: value))
                        : null,
                  ),
                  SwitchListTile(
                    title: Text(_text('Lane', '车道')),
                    subtitle: Text(
                      _text(
                        'Shown when available in NZTA data',
                        '按 NZTA 数据提供情况显示',
                      ),
                    ),
                    value: current.lane,
                    onChanged: current.cameras
                        ? (value) => update(current.copyWith(lane: value))
                        : null,
                  ),
                  SwitchListTile(
                    title: Text(_text('Other', '其他')),
                    value: current.other,
                    onChanged: current.cameras
                        ? (value) => update(current.copyWith(other: value))
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
