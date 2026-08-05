import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/scanner_service.dart';
import '../services/report_generator_service.dart';
import '../utils/permission_mapper.dart';
import '../theme.dart';

class ApkScanScreen extends StatefulWidget {
  const ApkScanScreen({super.key});

  @override
  State<ApkScanScreen> createState() => _ApkScanScreenState();
}

class _ApkScanScreenState extends State<ApkScanScreen> {
  final ScannerService _scannerService = ScannerService();
  bool _isScanning = false;
  bool _stopSimulation = false;
  bool _liveProgressActive = false;
  String? _fileName;
  String _progressMessage = '';
  Map<String, dynamic>? _report;
  String? _error;
  int _currentStepIndex = 0;
  final List<String> _scanSteps = [
    'Uploading APK',
    'APKTool',
    'JADX',
    'MobSF',
    'YARA',
    'VirusTotal',
    'Generating Report'
  ];

  /// Maps backend progress percentages onto the visible step list.
  int _stepIndexForPercentage(int percentage) {
    if (percentage >= 95) return _scanSteps.length - 1;
    if (percentage >= 50) return _scanSteps.length - 3;
    if (percentage >= 20) return 2;
    return 0;
  }

  void _applyLiveProgress(String message, int percentage) {
    if (!mounted) return;
    _liveProgressActive = true;
    _stopSimulation = true;
    final step = _stepIndexForPercentage(percentage);
    setState(() {
      _progressMessage = message;
      if (step > _currentStepIndex) _currentStepIndex = step;
    });
  }

  Future<void> _simulateProgress() async {
    final delays = [2, 4, 6, 6, 4, 4]; // Estimated time per step
    for (int i = 0; i < delays.length; i++) {
      if (_stopSimulation) break;
      await Future.delayed(Duration(seconds: delays[i]));
      if (_stopSimulation) break;
      if (mounted && _currentStepIndex < _scanSteps.length - 1) {
        setState(() {
          _currentStepIndex++;
        });
      }
    }
  }

  Future<void> _pickAndScanApk() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['apk'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _fileName = result.files.single.name;
          _isScanning = true;
          _stopSimulation = false;
          _liveProgressActive = false;
          _progressMessage = '';
          _error = null;
          _report = null;
          _currentStepIndex = 0;
        });

        _simulateProgress();
        final report = await _scannerService.scanApk(
          result.files.single,
          onProgress: _applyLiveProgress,
        );
        
        if (mounted) {
          _stopSimulation = true;
          while (_currentStepIndex < _scanSteps.length - 1) {
            setState(() { _currentStepIndex++; });
            await Future.delayed(const Duration(milliseconds: 600)); // Slower animation so it's actually visible
          }
          await Future.delayed(const Duration(milliseconds: 600)); // Pause at the final step before switching view
          setState(() {
            _report = report;
            _isScanning = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        _stopSimulation = true;
        setState(() {
          _error = e.toString();
          _isScanning = false;
        });
      }
    }
  }

  Widget _buildProgressSteps() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
          const SizedBox(width: 16),
          const Text(
            'Running Security Analysis...',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primary),
          ),
        ],
      ),
      if (_liveProgressActive && _progressMessage.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              const Icon(Icons.sensors, size: 14, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _progressMessage,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 24),
          ...List.generate(_scanSteps.length, (index) {
            final isCompleted = index < _currentStepIndex;
            final isCurrent = index == _currentStepIndex;
            
            Color iconColor = Colors.grey.withValues(alpha: 0.5);
            IconData icon = Icons.circle_outlined;
            
            if (isCompleted) {
              iconColor = AppColors.success;
              icon = Icons.check_circle;
            } else if (isCurrent) {
              iconColor = AppColors.primary;
              icon = Icons.sync;
            }

            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isCurrent ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCurrent ? AppColors.primary.withValues(alpha: 0.5) : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, color: iconColor, size: 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _scanSteps[index],
                      style: TextStyle(
                        color: isCompleted ? Colors.white : (isCurrent ? AppColors.primary : Colors.grey),
                        fontWeight: isCurrent || isCompleted ? FontWeight.bold : FontWeight.normal,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (isCurrent)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/icon.png', height: 28, width: 28, errorBuilder: (c,e,s) => const Icon(Icons.android, color: AppColors.primary)),
            const SizedBox(width: 8),
            const Text('APK Scanner'),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _isScanning ? null : _pickAndScanApk,
              icon: const Icon(Icons.upload_file),
              label: const Text('Select APK to Scan'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 24),
            
            if (_isScanning)
              Expanded(
                child: Center(
                  child: _buildProgressSteps(),
                ),
              ),
              
            if (_error != null)
              Expanded(
                child: Center(
                  child: Text('Error: $_error', style: const TextStyle(color: AppColors.danger)),
                ),
              ),
              
            if (_report != null)
              Expanded(
                child: SingleChildScrollView(
                  child: _buildReportView(_report!),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportView(Map<String, dynamic> report) {
    final risk = report['risk'] ?? {};
    final level = risk['level'] ?? 'UNKNOWN';
    final score = risk['score'] ?? 0;
    final aiExplanation = report['ai_explanation'] ?? 'No AI explanation available.';
    
    Color levelColor = AppColors.success;
    if (level == 'HIGH' || level == 'CRITICAL') {
      levelColor = AppColors.danger;
    } else if (level == 'MEDIUM') {
      levelColor = AppColors.warning;
    }

    final fileInfo = report['file_info'] ?? {};
    final permissions = (report['androguard']?['permissions'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final secrets = report['secrets']?['findings'] as Map<String, dynamic>? ?? {};
    final urls = (report['secrets']?['urls'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final certificates = (report['androguard']?['certificates'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final osint = report['osint'] ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Risk Score Card
        Card(
          color: levelColor.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: levelColor, width: 1.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Risk Level: $level', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: levelColor)),
                    const SizedBox(height: 4),
                    Text('Confidence Score: $score / 100', style: const TextStyle(fontSize: 16)),
                  ],
                ),
                Icon(
                  level == 'LOW' ? Icons.verified_user : Icons.warning_amber_rounded,
                  color: levelColor,
                  size: 48,
                )
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        
        // 2. AI Explanation Card
        const Text('AI Explanation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.smart_toy, color: AppColors.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    aiExplanation,
                    style: const TextStyle(fontSize: 15, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        if ((osint['virustotal'] as Map<String, dynamic>? ?? {}).isNotEmpty) ...[
          _buildSectionHeader('Threat Intelligence (OSINT)', Icons.travel_explore),
          _buildOsintCard(osint['virustotal'] as Map<String, dynamic>),
          const SizedBox(height: 16),
        ],

        _buildSectionHeader('File Information', Icons.insert_drive_file),
        _buildInfoCard([
          _buildInfoRow('MD5', fileInfo['md5'] ?? 'N/A'),
          _buildInfoRow('SHA-1', fileInfo['sha1'] ?? 'N/A'),
          _buildInfoRow('SHA-256', fileInfo['sha256'] ?? 'N/A'),
          _buildInfoRow('Size', '${((fileInfo['size'] ?? 0) / 1024 / 1024).toStringAsFixed(2)} MB'),
        ]),

        if (certificates.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildSectionHeader('Signer Certificates', Icons.verified),
          _buildInfoCard(
            certificates.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(c, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
            )).toList(),
          ),
        ],

        if (permissions.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildSectionHeader('Permissions (${permissions.length})', Icons.security),
          _buildPermissionsList(permissions),
        ],

        if (urls.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildSectionHeader('Extracted URLs & Trackers (${urls.length})', Icons.link),
          _buildInfoCard(
            urls.map((u) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.public, size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(child: Text(u, style: const TextStyle(fontSize: 13))),
                ],
              ),
            )).toList(),
          ),
        ],

        if (secrets.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildSectionHeader('Hardcoded Secrets (${secrets.length})', Icons.vpn_key),
          _buildInfoCard(
            secrets.entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.danger)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)),
                    child: Text(e.value.toString(), style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                  ),
                ],
              ),
            )).toList(),
          ),
        ],

        const SizedBox(height: 24),
        Center(
          child: ElevatedButton.icon(
            onPressed: () async {
              try {
                final file = await ReportGeneratorService.generateServerApkReport(
                  report: report,
                  fileName: _fileName ?? 'Unknown APK',
                );
                await OpenFilex.open(file.path);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to generate PDF: $e')),
                  );
                }
              }
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Export Detailed PDF Report'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildOsintCard(Map<String, dynamic> vt) {
    final status = (vt['status'] ?? 'error').toString();
    final malicious = (vt['malicious'] as num?)?.toInt() ?? 0;
    final suspicious = (vt['suspicious'] as num?)?.toInt() ?? 0;
    final undetected = (vt['undetected'] as num?)?.toInt() ?? 0;
    final link = (vt['link'] as String?) ?? '';

    final Color statusColor;
    if (status == 'success' && malicious > 0) {
      statusColor = AppColors.danger;
    } else if (status == 'success') {
      statusColor = AppColors.success;
    } else if (status == 'RATE_LIMITED') {
      statusColor = AppColors.warning;
    } else {
      statusColor = AppColors.textSecondary;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: statusColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'VirusTotal Engine Scan',
                    style: TextStyle(fontWeight: FontWeight.bold, color: statusColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (status == 'success')
              Row(
                children: [
                  _buildVtStat('Malicious', malicious, AppColors.danger),
                  _buildVtStat('Suspicious', suspicious, AppColors.warning),
                  _buildVtStat('Undetected', undetected, AppColors.success),
                ],
              )
            else if (status == 'not_found')
              const Text('Hash not found in VirusTotal database.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary))
            else if (status == 'RATE_LIMITED')
              const Text('VirusTotal rate limit reached. Retry later.',
                  style: TextStyle(fontSize: 12, color: AppColors.warning))
            else if (status == 'skipped')
              const Text('VirusTotal not configured on the backend.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary))
            else
              const Text('VirusTotal lookup failed.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            if (link.isNotEmpty) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () => _openUrl(link),
                child: const Row(
                  children: [
                    Icon(Icons.open_in_new, size: 14, color: AppColors.primary),
                    SizedBox(width: 6),
                    Text('Open VirusTotal report',
                        style: TextStyle(color: AppColors.primary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVtStat(String label, int value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  void _openUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildPermissionsList(List<String> permissions) {
    return _buildInfoCard(
      permissions.map((p) {
        final mapping = PermissionMapper.getRiskLevel(p);
        final level = mapping['level']!;
        final desc = mapping['desc']!;
        
        Color badgeColor = Colors.grey;
        if (level == 'Dangerous') {
          badgeColor = AppColors.danger;
        } else if (level == 'Signature') {
          badgeColor = AppColors.warning;
        } else if (level == 'Normal') {
          badgeColor = AppColors.success;
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2, right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(4)),
                    child: Text(level, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: Text(p.replaceAll('android.permission.', ''), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
              if (desc.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, left: 2),
                  child: Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}