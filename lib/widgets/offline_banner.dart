// lib/widgets/offline_banner.dart

import 'package:flutter/material.dart';
import '../services/app_capabilities_service.dart';
import '../theme.dart';

/// A banner that appears at the top of the app when the device is offline or
/// running in limited capability mode (backend unreachable or keys missing).
class OfflineBanner extends StatefulWidget {
  final Widget child;

  const OfflineBanner({super.key, required this.child});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _heightAnim;

  @override
  void initState() {
    super.initState();
    final initCaps = AppCapabilitiesService.capabilities.value;
    final showInitially = initCaps.isOfflineMode || !initCaps.hasFullAi || !initCaps.hasOsint;
    _controller = AnimationController(
      value: showInitially ? 1.0 : 0.0,
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _heightAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    AppCapabilitiesService.init();
    AppCapabilitiesService.capabilities.addListener(_onCapabilitiesChanged);
    _onCapabilitiesChanged();
  }

  void _onCapabilitiesChanged() {
    final caps = AppCapabilitiesService.capabilities.value;
    final showBanner = caps.isOfflineMode || !caps.hasFullAi || !caps.hasOsint;
    if (showBanner) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    AppCapabilitiesService.capabilities.removeListener(_onCapabilitiesChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ValueListenableBuilder<AppCapabilities>(
          valueListenable: AppCapabilitiesService.capabilities,
          builder: (context, caps, _) {
            final isOffline = caps.isOfflineMode;
            final isLimited = !caps.hasFullAi || !caps.hasOsint;

            if (!isOffline && !isLimited) {
              return const SizedBox.shrink();
            }

            final String message;
            final IconData icon;
            final Color bannerColor;

            if (isOffline) {
              message = 'LIMITED MODE: Device is offline. Using local heuristics only.';
              icon = Icons.wifi_off;
              bannerColor = AppColors.warning;
            } else {
              message = 'LIMITED MODE: ${caps.modeLabel}';
              icon = Icons.info_outline;
              bannerColor = AppColors.warning.withValues(alpha: 0.9);
            }

            return SizeTransition(
              sizeFactor: _heightAnim,
              axis: Axis.vertical,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                color: bannerColor,
                child: Row(
                  children: [
                    Icon(icon, color: Colors.black, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
