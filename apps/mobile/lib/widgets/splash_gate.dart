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
        : Scaffold(
            key: ValueKey('kiwi-splash'),
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/icon/tasman_lockup.png',
                      width: 315,
                      fit: BoxFit.contain,
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}
