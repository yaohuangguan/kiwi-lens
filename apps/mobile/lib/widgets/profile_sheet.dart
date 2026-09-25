import 'package:flutter/material.dart';

import '../data/account_repository.dart';

class ProfileSheet extends StatefulWidget {
  const ProfileSheet({super.key, required this.account});
  final AccountRepository account;

  @override
  State<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<ProfileSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool register = false;
  String? error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => error = null);
    try {
      await widget.account.authenticate(_email.text, _password.text, register: register);
      _password.clear();
    } catch (exception) {
      if (mounted) setState(() => error = '$exception'.replaceFirst('Bad state: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.account,
      builder: (context, _) {
        final profile = widget.account.profile;
        return Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(top: false, child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .82,
            child: ListView(padding: EdgeInsets.fromLTRB(20, 12, 20,
              MediaQuery.viewInsetsOf(context).bottom + 24), children: [
              Center(child: Container(width: 48, height: 5, margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(color: const Color(0xFFD0D8D2), borderRadius: BorderRadius.circular(6)))),
              Row(children: [
                const Expanded(child: Text('My Tasman', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900))),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
              ]),
              if (profile == null) ...[
                const SizedBox(height: 12),
                const Text('Explore as a guest, or sign in to sync trips, favorites and private reviews.'),
                const SizedBox(height: 18),
                TextField(controller: _email, keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email], decoration: const InputDecoration(
                    labelText: 'Email', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: _password, obscureText: true,
                  autofillHints: [register ? AutofillHints.newPassword : AutofillHints.password],
                  decoration: InputDecoration(labelText: register ? 'Password (12+ characters)' : 'Password',
                    border: const OutlineInputBorder())),
                if (error != null) Padding(padding: const EdgeInsets.only(top: 10),
                  child: Text(error!, style: const TextStyle(color: Colors.red))),
                const SizedBox(height: 14),
                FilledButton(onPressed: widget.account.loading ? null : _submit,
                  child: Text(register ? 'Create account' : 'Sign in')),
                TextButton(onPressed: () => setState(() => register = !register),
                  child: Text(register ? 'Already have an account? Sign in' : 'New here? Create an account')),
                const Text('Email verification and password recovery are not available yet.',
                  style: TextStyle(color: Colors.black54, fontSize: 12)),
              ] else ...[
                Text(profile.email, style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 16),
                Row(children: [
                  _Stat('${profile.routes.length}', 'Routes'),
                  _Stat('${profile.places.where((place) => place['isFavorite'] == true).length}', 'Favorites'),
                  _Stat('${profile.reviews.length}', 'Reviews'),
                ]),
                const SizedBox(height: 18),
                _Section(title: 'Recent navigation and saved routes', empty: 'No routes yet.',
                  items: profile.routes.map((route) {
                    final name = route['destinationName'] as String? ?? 'Destination';
                    final mode = route['mode'] as String? ?? 'drive';
                    final metres = (route['distanceMeters'] as num?)?.round();
                    return _ProfileRow(icon: Icons.route_rounded, title: name,
                      detail: '$mode${metres == null ? '' : ' · ${(metres / 1000).toStringAsFixed(1)} km'}');
                  }).toList()),
                _Section(title: 'Saved places', empty: 'No favorites or notes yet.',
                  items: profile.places.map((place) => _ProfileRow(
                    icon: place['isFavorite'] == true ? Icons.favorite_rounded : Icons.place_outlined,
                    title: place['name'] as String? ?? 'Place',
                    detail: (place['note'] as String?)?.isNotEmpty == true
                        ? place['note'] as String : (place['address'] as String? ?? ''),
                  )).toList()),
                _Section(title: 'My private reviews', empty: 'No reviews yet.',
                  items: profile.reviews.map((review) => _ProfileRow(
                    icon: Icons.star_rounded,
                    title: '${review['placeName'] ?? 'Place'} · ${'★' * ((review['rating'] as num?)?.round() ?? 0)}',
                    detail: review['comment'] as String? ?? '',
                  )).toList()),
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: () async {
                  await widget.account.signOut();
                  if (mounted) setState(() => error = null);
                }, icon: const Icon(Icons.logout_rounded), label: const Text('Sign out')),
              ],
            ]),
          )),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: const Color(0xFFF0F6E8), borderRadius: BorderRadius.circular(13)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
    ]),
  ));
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.empty, required this.items});
  final String title;
  final String empty;
  final List<Widget> items;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const SizedBox(height: 12),
    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
    if (items.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(empty, style: const TextStyle(color: Colors.black54)))
    else ...items,
  ]);
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: const Color(0xFF356A4F)),
    title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: detail.isEmpty ? null : Text(detail, maxLines: 3, overflow: TextOverflow.ellipsis),
  );
}
