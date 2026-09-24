import 'package:flutter/material.dart';

import '../domain/map_layer_settings.dart';

class MapLayerSheet extends StatefulWidget {
  const MapLayerSheet({
    super.key,
    required this.settings,
    required this.onChanged,
  });
  final MapLayerSettings settings;
  final ValueChanged<MapLayerSettings> onChanged;

  @override
  State<MapLayerSheet> createState() => _MapLayerSheetState();
}

class _MapLayerSheetState extends State<MapLayerSheet> {
  late MapLayerSettings current = widget.settings;

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
            const Text(
              'Map layers',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose what appears on the map. Camera alerts remain available during an active trip.',
              style: TextStyle(color: Color(0xFF607269), fontSize: 12),
            ),
            const SizedBox(height: 15),
            SegmentedButton<BaseMapStyle>(
              segments: const [
                ButtonSegment(
                  value: BaseMapStyle.standard,
                  icon: Icon(Icons.map_outlined),
                  label: Text('Map'),
                ),
                ButtonSegment(
                  value: BaseMapStyle.satellite,
                  icon: Icon(Icons.satellite_alt_outlined),
                  label: Text('Satellite'),
                ),
                ButtonSegment(
                  value: BaseMapStyle.terrain,
                  icon: Icon(Icons.terrain_outlined),
                  label: Text('Terrain'),
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
              title: const Text('Live traffic'),
              subtitle: const Text('Google traffic colours on the base map'),
              value: current.traffic,
              onChanged: (value) => update(current.copyWith(traffic: value)),
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.photo_camera_rounded),
              title: const Text('Safety cameras'),
              value: current.cameras,
              onChanged: (value) => update(current.copyWith(cameras: value)),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Speed'),
                    value: current.speed,
                    onChanged: current.cameras
                        ? (value) => update(current.copyWith(speed: value))
                        : null,
                  ),
                  SwitchListTile(
                    title: const Text('Red light'),
                    value: current.redLight,
                    onChanged: current.cameras
                        ? (value) => update(current.copyWith(redLight: value))
                        : null,
                  ),
                  SwitchListTile(
                    title: const Text('Lane'),
                    subtitle: const Text('Shown when available in NZTA data'),
                    value: current.lane,
                    onChanged: current.cameras
                        ? (value) => update(current.copyWith(lane: value))
                        : null,
                  ),
                  SwitchListTile(
                    title: const Text('Other'),
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
