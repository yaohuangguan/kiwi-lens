import '../theme/tasman_theme.dart';

import 'dart:async';

import 'package:flutter/material.dart';

class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});
  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  Timer? _timer;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1050), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 360),
    child: _ready
        ? KeyedSubtree(key: const ValueKey('kiwi-map'), child: widget.child)
        : const Scaffold(
            key: ValueKey('kiwi-splash'),
            backgroundColor: Color(0xFF0B1717),
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SplashMark(),
                    SizedBox(height: 24),
                    Text(
                      'TASMAN',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 31,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    SizedBox(height: 9),
                    Text(
                      'See the road ahead',
                      style: TextStyle(
                        color: TasmanColors.sky,
                        fontSize: 13,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}

class _SplashMark extends StatelessWidget {
  const _SplashMark();

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: Image.asset(
      'assets/icon/app_icon.png',
      width: 86,
      height: 86,
      fit: BoxFit.cover,
    ),
  );
}
