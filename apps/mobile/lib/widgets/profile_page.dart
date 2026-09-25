import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../data/account_repository.dart';
import '../domain/map_provider.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.account,
    required this.voiceEnabled,
    required this.lanesEnabled,
    required this.appLanguage,
    required this.voiceLanguage,
    required this.onVoiceChanged,
    required this.onLanesChanged,
    required this.onAppLanguageChanged,
    required this.onLanguageChanged,
    required this.onMapLayers,
    required this.mapProvider,
    required this.locationMarker,
    required this.onMapProviderChanged,
    required this.onLocationMarkerChanged,
    required this.mapboxAvailable,
  });

  final AccountRepository account;
  final bool voiceEnabled;
  final bool lanesEnabled;
  final String appLanguage;
  final String voiceLanguage;
  final ValueChanged<bool> onVoiceChanged;
  final ValueChanged<bool> onLanesChanged;
  final ValueChanged<String> onAppLanguageChanged;
  final ValueChanged<String> onLanguageChanged;
  final VoidCallback onMapLayers;
  final MapProvider mapProvider;
  final LocationMarkerStyle locationMarker;
  final Future<MapProvider> Function(MapProvider) onMapProviderChanged;
  final ValueChanged<LocationMarkerStyle> onLocationMarkerChanged;
  final bool mapboxAvailable;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  String? _error;
  late bool _voice = widget.voiceEnabled;
  late bool _lanes = widget.lanesEnabled;
  late String _appLanguage = widget.appLanguage;
  late String _language = widget.voiceLanguage;
  late MapProvider _mapProvider = widget.mapProvider;
  late LocationMarkerStyle _locationMarker = widget.locationMarker;

  String _text(String english, String chinese) =>
      _appLanguage == 'zh' ? chinese : english;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() => _error = null);
    try {
      await widget.account.authenticate(
        _email.text,
        _password.text,
        register: _register,
      );
      _password.clear();
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error'.replaceFirst('Bad state: ', ''));
      }
    }
  }

  Future<void> _google({bool link = false}) async {
    setState(() => _error = null);
    try {
      await widget.account.authenticateWithGoogle(link: link);
    } on GoogleSignInException catch (error) {
      if (error.code != GoogleSignInExceptionCode.canceled && mounted) {
        setState(
          () => _error =
              'Google sign-in: ${error.description ?? error.code.name}',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error'.replaceFirst('Bad state: ', ''));
      }
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(
      text: widget.account.profile?.displayName ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit display name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    try {
      await widget.account.updateDisplayName(name);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _voiceChanged(bool value) {
    setState(() => _voice = value);
    widget.onVoiceChanged(value);
    widget.account
        .updatePreferences(language: _appLanguage, voiceEnabled: value)
        .catchError((_) {});
  }

  void _languageChanged(String value) {
    setState(() => _language = value);
    widget.onLanguageChanged(value);
  }

  void _appLanguageChanged(String value) {
    setState(() => _appLanguage = value);
    widget.onAppLanguageChanged(value);
    widget.account
        .updatePreferences(language: value, voiceEnabled: _voice)
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.account,
    builder: (context, _) {
      final profile = widget.account.profile;
      return Scaffold(
        backgroundColor: const Color(0xFFF7F9F5),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B1717),
          foregroundColor: Colors.white,
          title: Text(
            _text('My Kiwi Lens', '我的 Kiwi Lens'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1717),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 27,
                      backgroundColor: const Color(0xFFC8F169),
                      child: Text(
                        profile?.displayName.isNotEmpty == true
                            ? profile!.displayName[0].toUpperCase()
                            : 'K',
                        style: const TextStyle(
                          color: Color(0xFF0B1717),
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile?.displayName.isNotEmpty == true
                                ? profile!.displayName
                                : profile == null
                                ? _text('Guest explorer', '访客')
                                : _text('Kiwi Lens member', 'Kiwi Lens 用户'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            profile?.email ??
                                _text(
                                  'Sign in to sync your trips and places',
                                  '登录以同步行程和地点',
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (profile != null)
                      IconButton(
                        onPressed: _editName,
                        tooltip: _text('Edit profile', '编辑资料'),
                        icon: const Icon(
                          Icons.edit_rounded,
                          color: Color(0xFFC8F169),
                        ),
                      ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 13),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFB44032)),
                  ),
                ),
              if (profile == null) ...[
                const SizedBox(height: 19),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: _text('Email', '邮箱'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: [
                    _register
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  decoration: InputDecoration(
                    labelText: _register
                        ? _text('Password (12+ characters)', '密码（至少 12 个字符）')
                        : _text('Password', '密码'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: widget.account.loading ? null : _signIn,
                  child: Text(
                    _register
                        ? _text('Create account', '创建账号')
                        : _text('Sign in', '登录'),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _register = !_register),
                  child: Text(
                    _register
                        ? _text('Already have an account? Sign in', '已有账号？登录')
                        : _text('New here? Create an account', '第一次使用？创建账号'),
                  ),
                ),
                Center(
                  child: Text(
                    _text('or', '或'),
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: widget.account.loading ? null : () => _google(),
                  icon: const Text(
                    'G',
                    style: TextStyle(
                      color: Color(0xFF4285F4),
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  label: Text(_text('Continue with Google', '使用 Google 继续')),
                ),
              ] else ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    _Stat('${profile.routes.length}', _text('Routes', '路线')),
                    _Stat(
                      '${profile.places.where((place) => place['isFavorite'] == true).length}',
                      _text('Saved', '收藏'),
                    ),
                    _Stat('${profile.reviews.length}', _text('Reviews', '评价')),
                  ],
                ),
                if (!profile.providers.contains('google'))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.link_rounded),
                    title: Text(_text('Link Google account', '关联 Google 账号')),
                    subtitle: Text(
                      _text(
                        'Use the same email address to sign in with Google later',
                        '以后可使用相同邮箱通过 Google 登录',
                      ),
                    ),
                    onTap: widget.account.loading
                        ? null
                        : () => _google(link: true),
                  ),
              ],
              const SizedBox(height: 18),
              _SectionTitle(_text('App', '应用')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.translate_rounded),
                title: Text(_text('App language', '应用语言')),
                trailing: DropdownButton<String>(
                  value: _appLanguage,
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'zh', child: Text('中文')),
                  ],
                  onChanged: (value) {
                    if (value != null) _appLanguageChanged(value);
                  },
                ),
              ),
              const SizedBox(height: 8),
              _SectionTitle(_text('Map', '地图')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.map_outlined),
                title: Text(_text('Map provider', '地图提供商')),
                trailing: DropdownButton<MapProvider>(
                  value: _mapProvider,
                  items: const [
                    DropdownMenuItem(
                      value: MapProvider.google,
                      child: Text('Google Maps'),
                    ),
                    DropdownMenuItem(
                      value: MapProvider.mapbox,
                      child: Text('Mapbox'),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    if (value == MapProvider.mapbox &&
                        !widget.mapboxAvailable) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _text(
                              'Mapbox access token is not configured for this build.',
                              '此版本尚未配置 Mapbox 访问令牌。',
                            ),
                          ),
                        ),
                      );
                      return;
                    }
                    final actual = await widget.onMapProviderChanged(value);
                    if (mounted) setState(() => _mapProvider = actual);
                  },
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.layers_outlined),
                title: Text(_text('Map style', '地图样式')),
                subtitle: Text(
                  _text(
                    'Default, satellite, terrain and hybrid',
                    '标准、卫星、地形和混合',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: widget.onMapLayers,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.navigation_outlined),
                title: Text(_text('Location marker', '位置标记')),
                trailing: DropdownButton<LocationMarkerStyle>(
                  value: _locationMarker,
                  items: const [
                    DropdownMenuItem(
                      value: LocationMarkerStyle.kiwi,
                      child: Text('Kiwi'),
                    ),
                    DropdownMenuItem(
                      value: LocationMarkerStyle.arrow,
                      child: Text('Arrow'),
                    ),
                    DropdownMenuItem(
                      value: LocationMarkerStyle.car,
                      child: Text('Car'),
                    ),
                    DropdownMenuItem(
                      value: LocationMarkerStyle.classic,
                      child: Text('Classic'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _locationMarker = value);
                    widget.onLocationMarkerChanged(value);
                  },
                ),
              ),
              const SizedBox(height: 8),
              _SectionTitle(_text('Navigation & voice', '导航与语音')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.volume_up_rounded),
                title: Text(
                  _text('Voice guidance & camera alerts', '语音导航与摄像头提醒'),
                ),
                value: _voice,
                onChanged: _voiceChanged,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.language_rounded),
                title: Text(_text('Camera alert language', '摄像头提醒语言')),
                trailing: DropdownButton<String>(
                  value: _language,
                  items: const [
                    DropdownMenuItem(value: 'en-NZ', child: Text('English')),
                    DropdownMenuItem(value: 'zh-CN', child: Text('中文')),
                  ],
                  onChanged: (value) {
                    if (value != null) _languageChanged(value);
                  },
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.alt_route_rounded),
                title: Text(_text('Lane guidance', '车道指引')),
                value: _lanes,
                onChanged: (value) {
                  setState(() => _lanes = value);
                  widget.onLanesChanged(value);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.layers_rounded),
                title: Text(_text('Map layers', '地图图层')),
                subtitle: Text(
                  _text('Cameras, traffic and map style', '摄像头、路况与地图样式'),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: widget.onMapLayers,
              ),
              if (profile != null) ...[
                const SizedBox(height: 12),
                _SectionTitle(_text('Your activity', '你的活动')),
                _ActivitySection(
                  'Recent routes',
                  Icons.route_rounded,
                  profile.routes
                      .map(
                        (item) =>
                            item['destinationName']?.toString() ?? 'Route',
                      )
                      .toList(),
                ),
                _ActivitySection(
                  'Saved places',
                  Icons.bookmark_rounded,
                  profile.places
                      .map((item) => item['name']?.toString() ?? 'Place')
                      .toList(),
                ),
                _ActivitySection(
                  'Your reviews',
                  Icons.rate_review_rounded,
                  profile.reviews
                      .map((item) => item['placeName']?.toString() ?? 'Place')
                      .toList(),
                ),
                const SizedBox(height: 15),
                OutlinedButton.icon(
                  onPressed: () async {
                    await widget.account.signOut();
                    if (mounted) setState(() => _error = null);
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      title,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F4D6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    ),
  );
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection(this.title, this.icon, this.items);
  final String title;
  final IconData icon;
  final List<String> items;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text('${items.length} items'),
    children: items.isEmpty
        ? [const ListTile(title: Text('Nothing here yet'))]
        : items.take(30).map((item) => ListTile(title: Text(item))).toList(),
  );
}
