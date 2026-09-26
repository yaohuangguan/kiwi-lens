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
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final activeBlue = dark ? TasmanColors.sky : TasmanColors.ocean;
    final activeSurface = dark
        ? TasmanColors.deepTeal.withValues(alpha: .20)
        : TasmanColors.sky.withValues(alpha: .10);
    final idleSurface = dark
        ? TasmanColors.darkSurface
        : scheme.surfaceContainerLow;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: visible || alert ? activeSurface : idleSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: visible || alert
              ? activeBlue.withValues(alpha: dark ? .48 : .28)
              : theme.dividerColor,
        ),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: visible || alert
                  ? activeBlue.withValues(alpha: dark ? .18 : .12)
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              icon,
              color: visible || alert ? activeBlue : scheme.onSurfaceVariant,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _text(en, zh),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
          ),
          Tooltip(
            message: _text('Show on map', '在地图显示'),
            child: Switch(
              value: visible,
              onChanged: onVisible,
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return dark ? TasmanColors.midnightOcean : Colors.white;
                }
                return dark ? TasmanColors.darkTextSecondary : Colors.white;
              }),
              trackColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return activeBlue;
                }
                return dark
                    ? TasmanColors.darkBorder
                    : TasmanColors.lightBorder;
              }),
              trackOutlineColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.transparent;
                }
                return dark
                    ? TasmanColors.darkBorder
                    : TasmanColors.lightBorder;
              }),
            ),
          ),
          const SizedBox(width: 3),
          Tooltip(
            message: _text('Alert while driving', '驾驶时提醒'),
            child: Material(
              color: alert
                  ? activeBlue.withValues(alpha: dark ? .22 : .12)
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
                side: BorderSide(
                  color: alert
                      ? activeBlue.withValues(alpha: .55)
                      : theme.dividerColor,
                ),
              ),
              child: InkWell(
                onTap: () => onAlert(!alert),
                borderRadius: BorderRadius.circular(11),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    alert
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    size: 19,
                    color: alert ? activeBlue : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  SwitchThemeData _tasmanLayerSwitchTheme(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final activeBlue = dark ? TasmanColors.sky : TasmanColors.ocean;
    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return Theme.of(context).disabledColor;
        }
        if (states.contains(WidgetState.selected)) {
          return dark ? TasmanColors.midnightOcean : Colors.white;
        }
        return dark ? TasmanColors.darkTextSecondary : Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return Theme.of(context).disabledColor.withValues(alpha: .20);
        }
        if (states.contains(WidgetState.selected)) return activeBlue;
        return dark ? TasmanColors.darkBorder : TasmanColors.lightBorder;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.transparent;
        return dark ? TasmanColors.darkBorder : TasmanColors.lightBorder;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .70,
      minChildSize: .28,
      maxChildSize: .88,
      snap: true,
      snapSizes: const [.42, .70, .88],
      shouldCloseOnMinExtent: true,
      builder: (context, scrollController) => Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 46,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).dividerColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 26),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _text('Map layers', '地图图层'),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: _text('Close', '关闭'),
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    Text(
                      _text(
                        'Choose what appears on the map and which cameras alert you while driving.',
                        '选择地图显示内容，以及驾驶时需要提醒的摄像头类型。',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
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
                    Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(switchTheme: _tasmanLayerSwitchTheme(context)),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: Icon(
                          Icons.traffic_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(_text('Live traffic', '实时交通')),
                        value:
                            widget.mapProvider == MapProvider.google &&
                            current.traffic,
                        onChanged: widget.mapProvider == MapProvider.google
                            ? (value) =>
                                  update(current.copyWith(traffic: value))
                            : null,
                      ),
                    ),
                    const Divider(),
                    Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(switchTheme: _tasmanLayerSwitchTheme(context)),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: Icon(
                          Icons.photo_camera_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(
                          _text('Fixed enforcement cameras', '固定执法摄像头'),
                        ),
                        subtitle: Text(
                          _text(
                            'Map visibility and driving alerts can be controlled separately.',
                            '地图显示和驾驶提醒可以分别控制。',
                          ),
                        ),
                        value: current.cameras,
                        onChanged: (value) =>
                            update(current.copyWith(cameras: value)),
                      ),
                    ),
                    _cameraToggle(
                      icon: Icons.speed_rounded,
                      en: 'Spot speed',
                      zh: '定点测速',
                      visible: current.spotSpeed,
                      onVisible: (v) => update(current.copyWith(spotSpeed: v)),
                      alert: current.alertSpotSpeed,
                      onAlert: (v) =>
                          update(current.copyWith(alertSpotSpeed: v)),
                    ),
                    _cameraToggle(
                      icon: Icons.social_distance_rounded,
                      en: 'Average speed',
                      zh: '区间测速',
                      visible: current.averageSpeed,
                      onVisible: (v) =>
                          update(current.copyWith(averageSpeed: v)),
                      alert: current.alertAverageSpeed,
                      onAlert: (v) =>
                          update(current.copyWith(alertAverageSpeed: v)),
                    ),
                    _cameraToggle(
                      icon: Icons.traffic_rounded,
                      en: 'Red light',
                      zh: '闯红灯',
                      visible: current.redLight,
                      onVisible: (v) => update(current.copyWith(redLight: v)),
                      alert: current.alertRedLight,
                      onAlert: (v) =>
                          update(current.copyWith(alertRedLight: v)),
                    ),
                    _cameraToggle(
                      icon: Icons.emergency_share_outlined,
                      en: 'Red light + speed',
                      zh: '闯红灯 + 测速',
                      visible: current.dualRedLightSpeed,
                      onVisible: (v) =>
                          update(current.copyWith(dualRedLightSpeed: v)),
                      alert: current.alertDualRedLightSpeed,
                      onAlert: (v) =>
                          update(current.copyWith(alertDualRedLightSpeed: v)),
                    ),
                    _cameraToggle(
                      icon: Icons.directions_bus_filled_rounded,
                      en: 'Bus / transit lane',
                      zh: '公交 / 多乘员车道',
                      visible: current.busLane,
                      onVisible: (v) => update(current.copyWith(busLane: v)),
                      alert: current.alertBusLane,
                      onAlert: (v) => update(current.copyWith(alertBusLane: v)),
                    ),
                    _cameraToggle(
                      icon: Icons.videocam_outlined,
                      en: 'Other enforcement cameras',
                      zh: '其他执法摄像头',
                      visible: current.other,
                      onVisible: (v) => update(current.copyWith(other: v)),
                      alert: current.alertOther,
                      onAlert: (v) => update(current.copyWith(alertOther: v)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _text(
                        'Only published fixed camera locations are mapped. Mobile camera locations are not fabricated.',
                        '只展示有公开位置的固定摄像头，不会伪造移动测速位置。',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
