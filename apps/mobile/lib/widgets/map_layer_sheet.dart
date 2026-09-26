import 'package:flutter/material.dart';

import '../domain/map_layer_settings.dart';
import '../domain/map_provider.dart';
import '../theme/tasman_theme.dart';

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

  Widget _cameraToggle({
    required IconData icon,
    required String en,
    required String zh,
    required bool visible,
    required ValueChanged<bool> onVisible,
    required bool alert,
    required ValueChanged<bool> onAlert,
    bool available = true,
  }) => Padding(
    padding: const EdgeInsets.only(left: 8, bottom: 6),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: TasmanColors.sky.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TasmanColors.sky.withValues(alpha: .18)),
      ),
      child: Column(
        children: [
          SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            secondary: Icon(icon, color: TasmanColors.ocean),
            title: Text(_text(en, zh), style: const TextStyle(fontWeight: FontWeight.w700)),
            value: available && visible,
            onChanged: available ? onVisible : null,
          ),
          const Divider(height: 1, indent: 48),
          SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 48, right: 12),
            secondary: const Icon(Icons.notifications_active_outlined, size: 20),
            title: Text(_text('Alert while driving', '驾驶时提醒')),
            value: available && alert,
            onChanged: available ? onAlert : null,
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(27)),
      child: SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            Center(
              child: Container(
                width: 46,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(_text('Map layers', '地图图层'),
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text(
              _text(
                'Map visibility and driving alerts are independent.',
                '地图显示与驾驶提醒可分别设置。',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 15),
            SegmentedButton<BaseMapStyle>(
              segments: [
                ButtonSegment(value: BaseMapStyle.standard, icon: const Icon(Icons.map_outlined), label: Text(_text('Map', '地图'))),
                ButtonSegment(value: BaseMapStyle.satellite, icon: const Icon(Icons.satellite_alt_outlined), label: Text(_text('Satellite', '卫星'))),
                ButtonSegment(value: BaseMapStyle.terrain, icon: const Icon(Icons.terrain_outlined), label: Text(_text('Terrain', '地形'))),
              ],
              selected: {current.style == BaseMapStyle.hybrid ? BaseMapStyle.satellite : current.style},
              onSelectionChanged: (value) => update(current.copyWith(style: value.first)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.traffic_rounded),
              title: Text(_text('Live traffic', '实时交通')),
              value: widget.mapProvider == MapProvider.google && current.traffic,
              onChanged: widget.mapProvider == MapProvider.google
                  ? (value) => update(current.copyWith(traffic: value))
                  : null,
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.photo_camera_rounded),
              title: Text(_text('NZTA fixed safety cameras', 'NZTA 固定安全摄像头')),
              subtitle: Text(_text(
                'Spot speed, average speed and red-light cameras published by NZTA',
                '显示 NZTA 公布的定点测速、区间测速和闯红灯摄像头',
              )),
              value: current.cameras,
              onChanged: (value) => update(current.copyWith(cameras: value)),
            ),
            _cameraToggle(
              icon: Icons.speed_rounded,
              en: 'Spot speed', zh: '定点测速',
              visible: current.spotSpeed,
              onVisible: (v) => update(current.copyWith(spotSpeed: v)),
              alert: current.alertSpotSpeed,
              onAlert: (v) => update(current.copyWith(alertSpotSpeed: v)),
            ),
            _cameraToggle(
              icon: Icons.social_distance_rounded,
              en: 'Average speed', zh: '区间测速',
              visible: current.averageSpeed,
              onVisible: (v) => update(current.copyWith(averageSpeed: v)),
              alert: current.alertAverageSpeed,
              onAlert: (v) => update(current.copyWith(alertAverageSpeed: v)),
            ),
            _cameraToggle(
              icon: Icons.traffic_rounded,
              en: 'Red light', zh: '闯红灯',
              visible: current.redLight,
              onVisible: (v) => update(current.copyWith(redLight: v)),
              alert: current.alertRedLight,
              onAlert: (v) => update(current.copyWith(alertRedLight: v)),
            ),
            _cameraToggle(
              icon: Icons.emergency_share_outlined,
              en: 'Dual red light + speed', zh: '闯红灯 + 测速',
              visible: current.dualRedLightSpeed,
              onVisible: (v) => update(current.copyWith(dualRedLightSpeed: v)),
              alert: current.alertDualRedLightSpeed,
              onAlert: (v) => update(current.copyWith(alertDualRedLightSpeed: v)),
            ),
            _cameraToggle(
              icon: Icons.videocam_outlined,
              en: 'Other published fixed cameras', zh: '其他已公布固定摄像头',
              visible: current.other,
              onVisible: (v) => update(current.copyWith(other: v)),
              alert: current.alertOther,
              onAlert: (v) => update(current.copyWith(alertOther: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Text(
                _text(
                  'NZTA mobile safety cameras are not mapped because their live locations are not published.',
                  'NZTA 不公开移动测速摄像头的实时位置，因此不会在地图上伪造显示。',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
