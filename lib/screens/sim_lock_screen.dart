import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:app_settings/app_settings.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import '../utils/debug_utils.dart';

/// Risk level for the security patch age.
enum PatchRisk { upToDate, outdated, criticallyOutdated, unknown }

class SimLockScreen extends StatefulWidget {
  const SimLockScreen({super.key});

  @override
  State<SimLockScreen> createState() => _SimLockScreenState();
}

class _SimLockScreenState extends State<SimLockScreen> {
  Map<String, String> _deviceInfo = {};
  bool _isLoading = true;

  // Derived risk signals
  PatchRisk _patchRisk = PatchRisk.unknown;
  int _patchAgeMonths = -1;
  String _patchDate = 'Unknown';
  bool _isEmulator = false;
  bool _isRooted = false;
  bool _hardwareEncryptionActive = false;
  String _overallRiskLevel = 'Unknown';
  Color _overallRiskColor = AppColors.textSecondary;
  List<String> _remediationSteps = [];

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  /// Parses the Android security patch string (YYYY-MM-DD) and returns the
  /// number of whole months elapsed since that date.
  int _monthsAgoPatch(String patchString) {
    try {
      final parts = patchString.split('-');
      if (parts.length != 3) return -1;
      final patchDate = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
      final now = DateTime.now();
      return (now.year - patchDate.year) * 12 + (now.month - patchDate.month);
    } catch (_) {
      return -1;
    }
  }

  PatchRisk _evaluatePatchRisk(int months) {
    if (months < 0) return PatchRisk.unknown;
    if (months <= 3) return PatchRisk.upToDate;
    if (months <= 6) return PatchRisk.outdated;
    return PatchRisk.criticallyOutdated;
  }

  Future<void> _loadDeviceInfo() async {
    setState(() => _isLoading = true);
    final plugin = DeviceInfoPlugin();
    final info = <String, String>{};
    final steps = <String>[];

    try {
      if (Platform.isAndroid) {
        final d = await plugin.androidInfo;
        info['Device'] = '${d.manufacturer} ${d.model}';
        info['Android Version'] = 'Android ${d.version.release} (SDK ${d.version.sdkInt})';
        info['Brand'] = d.brand;
        info['Hardware'] = d.hardware;

        // Security patch age
        _patchDate = d.version.securityPatch ?? 'Unknown';
        info['Security Patch'] = _patchDate;
        _patchAgeMonths = _monthsAgoPatch(_patchDate);
        _patchRisk = _evaluatePatchRisk(_patchAgeMonths);

        // Emulator detection
        _isEmulator = !d.isPhysicalDevice;
        info['Device Type'] = _isEmulator ? 'Emulator (not a real device)' : 'Physical device';

        // Native security checks via method channel
        try {
          const channel = MethodChannel('com.example.scamshield/security');
          // Add timeout to prevent indefinite hangs
          final nativeRes = await channel.invokeMethod<Map?>('checkDeviceIntegrity').timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              appDebugPrint('Device integrity check timed out after 5 seconds', tag: 'SimLockScreen');
              return null;
            },
          );
          
          if (nativeRes != null && nativeRes.isNotEmpty) {
            _isRooted = nativeRes['isRooted'] == true;
            _hardwareEncryptionActive = nativeRes['isHardwareEncrypted'] == true;
            final unknownSources = nativeRes['unknownSourcesEnabled'] == true;
            final bootloaderUnlocked = nativeRes['bootloaderUnlocked'] == true;
            // Log successful native channel call for debugging
            appDebugPrint('Device integrity check completed successfully', tag: 'SimLockScreen');

            info['Root / Integrity Status'] =
                _isRooted ? 'ROOTED / MODIFIED' : 'Clean (not rooted)';
            info['Hardware Encryption'] =
                _hardwareEncryptionActive ? 'Active (verified)' : 'Disabled or unavailable';
            info['Unknown Sources'] =
                unknownSources ? 'ENABLED (sideloading allowed)' : 'Disabled';
            info['Bootloader'] =
                bootloaderUnlocked ? 'UNLOCKED' : 'Locked';

            if (_isRooted) steps.add('Remove root access or reflash a clean OS image.');
            if (unknownSources) {
              steps.add('Disable "Install unknown apps" in Settings → Apps → Special access.');
            }
            if (bootloaderUnlocked) {
              steps.add('Re-lock the bootloader via fastboot if no longer needed.');
            }
            if (!_hardwareEncryptionActive) {
              steps.add('Enable device encryption in Settings → Security → Encryption.');
            }
          } else {
            info['Root Status'] = 'Not verified';
            info['Hardware Encryption'] = 'Not verified';
          }
        } on PlatformException catch (e) {
          appErrorPrint('Platform exception in device integrity check: ${e.code} - ${e.message}', tag: 'SimLockScreen');
          info['Root Status'] = 'Not verified (native bridge unavailable)';
          info['Hardware Encryption'] = 'Not verified';
        } catch (e) {
          appErrorPrint('Error in device integrity check: $e', tag: 'SimLockScreen');
          info['Root Status'] = 'Not verified (native bridge unavailable)';
          info['Hardware Encryption'] = 'Not verified';
        }

        // Patch remediation advice
        switch (_patchRisk) {
          case PatchRisk.criticallyOutdated:
            steps.insert(0,
                'URGENT: Install the latest security update immediately — '
                'your patch is $_patchAgeMonths months old. '
                'Tap "Check for Updates" below.');
            break;
          case PatchRisk.outdated:
            steps.insert(0,
                'Your security patch is $_patchAgeMonths months old. '
                'Apply pending system updates soon.');
            break;
          case PatchRisk.upToDate:
            break;
          case PatchRisk.unknown:
            steps.insert(
                0, 'Security patch date could not be determined. Check for updates manually.');
            break;
        }

        // Device & SIM protection steps (always recommended)
        steps.add('Enable SIM PIN in Settings → Security → SIM card lock to prevent unauthorized SIM swaps.');
        steps.add(
            'Contact your mobile carrier and set a verbal password to authorize SIM changes.');
        steps.add(
            'Switch 2FA from SMS to an authenticator app (e.g. Google Authenticator) — it\'s more secure.');

        // Overall risk level
        int riskPoints = 0;
        if (_patchRisk == PatchRisk.criticallyOutdated) riskPoints += 40;
        if (_patchRisk == PatchRisk.outdated) riskPoints += 20;
        if (_isRooted) riskPoints += 30;
        if (!_hardwareEncryptionActive) riskPoints += 15;
        if (_isEmulator) riskPoints += 10;

        if (riskPoints >= 50) {
          _overallRiskLevel = 'HIGH RISK';
          _overallRiskColor = AppColors.danger;
        } else if (riskPoints >= 20) {
          _overallRiskLevel = 'MEDIUM RISK';
          _overallRiskColor = AppColors.warning;
        } else {
          _overallRiskLevel = 'LOW RISK';
          _overallRiskColor = AppColors.success;
        }
      } else if (Platform.isIOS) {
        final d = await plugin.iosInfo;
        info['Device'] = d.name;
        info['Model'] = d.model;
        info['iOS Version'] = d.systemVersion;
        info['Is Physical Device'] = d.isPhysicalDevice ? 'Yes' : 'No (Simulator)';
        info['Root / Jailbreak Status'] = 'Not verified';
        info['Hardware Encryption'] = 'Not verified';
        _overallRiskLevel = 'Not Verified';
        _overallRiskColor = AppColors.textSecondary;
        steps.add(
            'Keep iOS updated via Settings → General → Software Update.');
        steps.add('Enable SIM PIN via Settings → Phone → SIM PIN to prevent SIM-swap attacks.');
      }
    } catch (_) {
      info['Error'] = 'Could not read device info';
    }

    if (mounted) {
      setState(() {
        _deviceInfo = info;
        _remediationSteps = steps;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Security Check',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Reveal(delay: Reveal.step(0), child: _buildOverallRiskCard()),
                const SizedBox(height: 16),
                if (Platform.isAndroid) ...[
                  Reveal(delay: Reveal.step(1), child: _buildPatchStatusCard()),
                  const SizedBox(height: 16),
                ],
                Reveal(delay: Reveal.step(2), child: _buildDeviceInfoCard()),
                const SizedBox(height: 16),
                Reveal(delay: Reveal.step(3), child: _buildSimSwapWarnings()),
                const SizedBox(height: 16),
                if (_remediationSteps.isNotEmpty) ...[
                  Reveal(delay: Reveal.step(4), child: _buildRemediationCard()),
                  const SizedBox(height: 16),
                ],
                Reveal(delay: Reveal.step(5), child: _buildActionButtons()),
                const SizedBox(height: 20),
              ],
            ),
    );
  }

  Widget _buildOverallRiskCard() {
    return GestureDetector(
      onTap: () => HapticFeedback.lightImpact(),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _overallRiskColor.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(color: _overallRiskColor.withValues(alpha: 0.12), blurRadius: 20),
          ],
        ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _overallRiskColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _overallRiskLevel.contains('HIGH')
                  ? Icons.shield_outlined
                  : _overallRiskLevel.contains('MEDIUM')
                      ? Icons.warning_amber_rounded
                      : Icons.verified_user_outlined,
              color: _overallRiskColor,
              size: 36,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _overallRiskLevel,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _overallRiskColor,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'SIM Swap & Device Integrity Assessment',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildPatchStatusCard() {
    Color patchColor;
    IconData patchIcon;
    String patchLabel;

    switch (_patchRisk) {
      case PatchRisk.upToDate:
        patchColor = AppColors.success;
        patchIcon = Icons.check_circle_outline;
        patchLabel = 'Up to date';
        break;
      case PatchRisk.outdated:
        patchColor = AppColors.warning;
        patchIcon = Icons.update_outlined;
        patchLabel = 'Outdated ($_patchAgeMonths months ago)';
        break;
      case PatchRisk.criticallyOutdated:
        patchColor = AppColors.danger;
        patchIcon = Icons.gpp_bad_outlined;
        patchLabel = 'Critically outdated ($_patchAgeMonths months ago)';
        break;
      case PatchRisk.unknown:
        patchColor = AppColors.textSecondary;
        patchIcon = Icons.help_outline;
        patchLabel = 'Unknown';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: patchColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: patchColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: patchColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(patchIcon, color: patchColor, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SECURITY PATCH LEVEL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _patchDate,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  patchLabel,
                  style: TextStyle(
                      color: patchColor, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
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
              Text(
                'DEVICE HARDWARE INTELLIGENCE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._deviceInfo.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(e.key,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.value,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: AppColors.textPrimary,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ),
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
              Text(
                'SIM SWAP THREAT INDICATORS',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.warning),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            '• Unexpected "No Service" when in normal coverage area.\n'
            '• Unsolicited SMS from your carrier about a SIM change or port.\n'
            '• Sudden loss of mobile data and 2FA SMS messages.\n'
            '• OTP codes stop arriving or appear on a different device.',
            style: TextStyle(fontSize: 12, height: 1.55, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildRemediationCard() {
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
              Icon(Icons.verified_user_outlined, color: AppColors.success, size: 18),
              SizedBox(width: 8),
              Text(
                'RECOMMENDED ACTIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._remediationSteps.asMap().entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${entry.key + 1}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: const TextStyle(
                            fontSize: 12, height: 1.5, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          height: 52,
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _openSystemUpdate,
            icon: const Icon(Icons.system_update_outlined, color: Colors.black),
            label: const Text(
              'CHECK FOR SYSTEM UPDATES',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              try {
                AppSettings.openAppSettings(type: AppSettingsType.security);
              } catch (_) {
                AppSettings.openAppSettings();
              }
            },
            icon: const Icon(Icons.security_outlined, color: AppColors.primary),
            label: const Text(
              'OPEN SECURITY SETTINGS',
              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  /// Deep-links to the system update settings page.
  /// Falls back to general settings if the intent is unavailable.
  void _openSystemUpdate() {
    try {
      const channel = MethodChannel('com.example.scamshield/security');
      channel.invokeMethod('openSystemUpdate');
    } catch (_) {
      try {
        AppSettings.openAppSettings(type: AppSettingsType.settings);
      } catch (_) {
        AppSettings.openAppSettings();
      }
    }
  }
}