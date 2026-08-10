// lib/widgets/offline_banner.dart

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../theme.dart';

/// A banner that appears at the top of the page when the device is offline.
/// Disappears automatically once connectivity is restored.
class OfflineBanner extends StatefulWidget {
  final Widget child;

  const OfflineBanner({super.key, required this.child});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner>
    with SingleTickerProviderStateMixin {
  bool _isOffline = false;
  late final AnimationController _controller;
  late final Animation<double> _heightAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _heightAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    // Listen to connectivity changes
    Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (offline != _isOffline) {
        setState(() => _isOffline = offline);
        if (offline) {
          _controller.forward();
        } else {
          _controller.reverse();
        }
      }
    });

    // Check current state on startup
    _checkInitial();
  }

  Future<void> _checkInitial() async {
    final results = await Connectivity().checkConnectivity();
    final offline = results.every((r) => r == ConnectivityResult.none);
    if (offline && mounted) {
      setState(() => _isOffline = true);
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizeTransition(
          sizeFactor: _heightAnim,
          axis: Axis.vertical,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: AppColors.warning.withValues(alpha: 0.9),
            child: const Row(
              children: [
                Icon(Icons.wifi_off, color: Colors.black, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You are offline. Some features require a network connection.',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
