import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:app_settings/app_settings.dart';
import '../theme.dart';
import '../widgets/motion.dart';

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
        try {
          const channel = MethodChannel('com.example.scamshield/security');
          final nativeRes = await channel.invokeMethod<Map>('checkDeviceIntegrity');
          if (nativeRes != null) {
            info['Root Status'] = nativeRes['isRooted'] == true ? 'Rooted / Modified' : 'Clean (Not Rooted)';
            info['Hardware Encryption'] = nativeRes['isHardwareEncrypted'] == true ? 'Active (Verified)' : 'Disabled';
          } else {
            info['Root Status'] = 'Not verified';
            info['Hardware Encryption'] = 'Not verified';
          }
        } catch (_) {
          info['Root Status'] = 'Not verified';
          info['Hardware Encryption'] = 'Not verified';
        }
      } else if (Platform.isIOS) {
        final d = await plugin.iosInfo;
        info['Device'] = d.name;
        info['Model'] = d.model;
        info['iOS Version'] = d.systemVersion;
        info['System Name'] = d.systemName;
        info['Is Physical Device'] = d.isPhysicalDevice ? 'Yes' : 'No (Simulator)';
        info['Root / Jailbreak Status'] = 'Not verified';
        info['Hardware Encryption'] = 'Not verified';
      }
    } catch (_) {
      info['Error'] = 'Could not read device info';
    }

    if (mounted) {
      setState(() {
        _deviceInfo = info;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SIM & Device Hardware Guard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Reveal(delay: Reveal.step(0), child: _buildStatusCard()),
                const SizedBox(height: 16),
                Reveal(delay: Reveal.step(1), child: _buildDeviceInfoCard()),
                const SizedBox(height: 16),
                Reveal(delay: Reveal.step(2), child: _buildSimSwapWarnings()),
                const SizedBox(height: 16),
                Reveal(delay: Reveal.step(3), child: _buildProtectionTips()),
                const SizedBox(height: 20),
                Reveal(delay: Reveal.step(4), child: _buildSetSimLockButton()),
              ],
            ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 16),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: const Icon(Icons.sd_card, color: AppColors.primary, size: 36),
          ),
          const SizedBox(height: 14),
          const Text('SIM Swap & Port Security', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
            'Protects your phone number from unauthorized carrier transfer and SMS 2FA interception.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceInfoCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.phone_android, color: AppColors.primary, size: 18),
              SizedBox(width: 8),
              Text('DEVICE HARDWARE INTELLIGENCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 12),
          ..._deviceInfo.entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(e.key, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                Text(e.value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildSimSwapWarnings() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
              SizedBox(width: 8),
              Text('SIM SWAP THREAT INDICATORS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.warning)),
            ],
          ),
          SizedBox(height: 10),
          Text(
            '• Unexpected "No Service" status when in normal coverage.\n'
            '• Unrequested SMS from your mobile carrier about SIM change.\n'
            '• Sudden loss of mobile data & 2FA SMS messages.',
            style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildProtectionTips() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, color: AppColors.success, size: 18),
              SizedBox(width: 8),
              Text('RECOMMENDED HARDWARE ACTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1)),
            ],
          ),
          SizedBox(height: 10),
          Text(
            '1. Enable SIM PIN in device security settings.\n'
            '2. Contact your mobile operator and request a Verbal Passcode for porting.\n'
            '3. Migrate 2FA from SMS to Authenticator App or FIDO2 keys.',
            style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildSetSimLockButton() {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () {
          try {
            AppSettings.openAppSettings(type: AppSettingsType.security);
          } catch (_) {
            AppSettings.openAppSettings();
          }
        },
        icon: const Icon(Icons.settings, color: Colors.black),
        label: const Text('OPEN DEVICE SECURITY SETTINGS', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
      ),
    );
  }
}
