import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../data/account_repository.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.account,
    required this.voiceEnabled,
    required this.lanesEnabled,
    required this.useCarMarker,
    required this.voiceLanguage,
    required this.onVoiceChanged,
    required this.onLanesChanged,
    required this.onCarMarkerChanged,
    required this.onLanguageChanged,
    required this.onMapLayers,
  });

  final AccountRepository account;
  final bool voiceEnabled;
  final bool lanesEnabled;
  final bool useCarMarker;
  final String voiceLanguage;
  final ValueChanged<bool> onVoiceChanged;
  final ValueChanged<bool> onLanesChanged;
  final ValueChanged<bool> onCarMarkerChanged;
  final ValueChanged<String> onLanguageChanged;
  final VoidCallback onMapLayers;

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
  late bool _car = widget.useCarMarker;
  late String _language = widget.voiceLanguage;

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
        .updatePreferences(language: _language, voiceEnabled: value)
        .catchError((_) {});
  }

  void _languageChanged(String value) {
    setState(() => _language = value);
    widget.onLanguageChanged(value);
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
          title: const Text(
            'My Kiwi Lens',
            style: TextStyle(fontWeight: FontWeight.w900),
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
                                ? 'Guest explorer'
                                : 'Kiwi Lens member',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            profile?.email ??
                                'Sign in to sync your trips and places',
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
                        tooltip: 'Edit profile',
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
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
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
                        ? 'Password (12+ characters)'
                        : 'Password',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: widget.account.loading ? null : _signIn,
                  child: Text(_register ? 'Create account' : 'Sign in'),
                ),
                TextButton(
                  onPressed: () => setState(() => _register = !_register),
                  child: Text(
                    _register
                        ? 'Already have an account? Sign in'
                        : 'New here? Create an account',
                  ),
                ),
                const Center(
                  child: Text('or', style: TextStyle(color: Colors.black54)),
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
                  label: const Text('Continue with Google'),
                ),
              ] else ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    _Stat('${profile.routes.length}', 'Routes'),
                    _Stat(
                      '${profile.places.where((place) => place['isFavorite'] == true).length}',
                      'Saved',
                    ),
                    _Stat('${profile.reviews.length}', 'Reviews'),
                  ],
                ),
                if (!profile.providers.contains('google'))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.link_rounded),
                    title: const Text('Link Google account'),
                    subtitle: const Text(
                      'Use the same email address to sign in with Google later',
                    ),
                    onTap: widget.account.loading
                        ? null
                        : () => _google(link: true),
                  ),
              ],
              const SizedBox(height: 18),
              const _SectionTitle('Navigation & voice'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.volume_up_rounded),
                title: const Text('Voice guidance & camera alerts'),
                value: _voice,
                onChanged: _voiceChanged,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.language_rounded),
                title: const Text('Camera alert language'),
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
                title: const Text('Lane guidance'),
                value: _lanes,
                onChanged: (value) {
                  setState(() => _lanes = value);
                  widget.onLanesChanged(value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.directions_car_filled_rounded),
                title: const Text('Car location icon'),
                subtitle: const Text('Replace the blue dot on the map'),
                value: _car,
                onChanged: (value) {
                  setState(() => _car = value);
                  widget.onCarMarkerChanged(value);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.layers_rounded),
                title: const Text('Map layers'),
                subtitle: const Text('Cameras, traffic and map style'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: widget.onMapLayers,
              ),
              if (profile != null) ...[
                const SizedBox(height: 12),
                const _SectionTitle('Your activity'),
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
