// lib/screens/sim_lock_screen.dart
// Real SIM lock & device security info screen.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:app_settings/app_settings.dart';
import '../theme.dart';

class SimLockScreen extends StatefulWidget {
  const SimLockScreen({super.key});

  @override
  State<SimLockScreen> createState() => _SimLockScreenState();
}

class _SimLockScreenState extends State<SimLockScreen> {
  Map<String, String> _deviceInfo = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    setState(() => _isLoading = true);
    final plugin = DeviceInfoPlugin();
    final info = <String, String>{};

    try {
      if (Platform.isAndroid) {
        final d = await plugin.androidInfo;
        info['Device'] = '${d.manufacturer} ${d.model}';
        info['Android Version'] = d.version.release;
        info['SDK'] = '${d.version.sdkInt}';
        info['Security Patch'] = d.version.securityPatch ?? 'Unknown';
        info['Brand'] = d.brand;
        info['Hardware'] = d.hardware;
        info['Is Physical Device'] = d.isPhysicalDevice ? 'Yes' : 'No (Emulator)';
      } else if (Platform.isIOS) {
        final d = await plugin.iosInfo;
        info['Device'] = d.name;
        info['Model'] = d.model;
        info['iOS Version'] = d.systemVersion;
        info['System Name'] = d.systemName;
        info['Is Physical Device'] = d.isPhysicalDevice ? 'Yes' : 'No (Simulator)';
      }
    } catch (_) {
      info['Error'] = 'Could not read device info';
    }

    if (!mounted) return;
    setState(() {
      _deviceInfo = info;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SIM & Device Security',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildStatusCard(),
                const SizedBox(height: 16),
                _buildDeviceInfoCard(),
                const SizedBox(height: 16),
                _buildSimSwapWarnings(),
                const SizedBox(height: 16),
                _buildProtectionTips(),
                const SizedBox(height: 16),
                _buildSetSimLockButton(),
              ],
            ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.2), AppColors.surface],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Text('📡', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text('SIM Swap Protection',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'SIM swap attacks let fraudsters hijack your phone number to steal OTPs. Learn how to protect yourself.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceInfoCard() {
    if (_deviceInfo.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.phone_android, color: AppColors.primary, size: 18),
              SizedBox(width: 8),
              Text('Device Information',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 14),
          ..._deviceInfo.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(e.key,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ),
                    Expanded(
                      child: Text(e.value,
                          style: const TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 12)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildSimSwapWarnings() {
    final warnings = [
      ('Sudden loss of network signal', AppColors.danger,
          'Your phone shows "No Service" or "Emergency Only" without reason — could indicate a SIM swap in progress.'),
      ('Unable to make calls/texts', AppColors.danger,
          'If calls and SMS stop working unexpectedly, your SIM may have been deactivated.'),
      ('Unexpected OTPs received', AppColors.warning,
          'Receiving OTPs you did not request is a sign someone is trying to access your accounts.'),
      ('Account login notifications', AppColors.warning,
          'Alerts for logins to Gmail, banking, etc. from unknown devices.'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
              SizedBox(width: 8),
              Text('SIM Swap Warning Signs',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 14),
          ...warnings.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: w.$2,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(w.$1,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(w.$3,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                  height: 1.4)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildProtectionTips() {
    final tips = [
      ('Set a SIM PIN', Icons.lock, 'Go to Settings → SIM card management → SIM lock to set a PIN that is needed before your SIM works in any device.'),
      ('Enable SIM lock with carrier', Icons.sim_card, 'Call your telecom provider (Airtel, Jio, Vi, etc.) and request a port-out freeze or SIM swap protection.'),
      ('Use Authenticator apps', Icons.security, 'Use Google Authenticator or Microsoft Authenticator instead of SMS OTPs for important accounts.'),
      ('Set up alerts', Icons.notifications_active, 'Enable login alerts for your banking and email apps to catch unauthorised access quickly.'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield, color: AppColors.success, size: 18),
              SizedBox(width: 8),
              Text('Protection Tips',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 14),
          ...tips.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(t.$2, color: AppColors.success, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.$1,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 3),
                          Text(t.$3,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                  height: 1.4)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildSetSimLockButton() {
    return ElevatedButton.icon(
      onPressed: () {
        if (Platform.isAndroid) {
          // Open Android security settings
          AppSettings.openAppSettings(type: AppSettingsType.security);
        } else {
          // iOS: guide user to Settings
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Go to Settings → Cellular → SIM PIN to set a SIM lock'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      icon: const Icon(Icons.lock_open, color: Colors.black),
      label: const Text('Open Security Settings',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
