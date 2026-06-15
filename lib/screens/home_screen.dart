// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import '../theme.dart';
import '../data/repositories/scan_repository.dart';
import '../data/models/scan_record.dart';
import '../data/education/daily_tips.dart';
import '../widgets/offline_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScanRepository _repo = ScanRepository();

  ScanStatistics? _stats;
  List<ScanRecord> _recentThreats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _repo.getStatistics();
      // Fetch only scam/suspicious records as "threat activity"
      final scams = await _repo.filterByClassification('scam');
      final suspicious = await _repo.filterByClassification('suspicious');
      final threats = [...scams, ...suspicious]
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      setState(() {
        _stats = stats;
        _recentThreats = threats.take(3).toList();
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OfflineBanner(
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const Icon(Icons.shield, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('ScamShield', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            const Icon(Icons.notifications_none),
            const SizedBox(width: 16),
            const CircleAvatar(
              radius: 15,
              backgroundImage: NetworkImage('https://i.pravatar.cc/150?u=yash'),
              backgroundColor: AppColors.surface,
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _loadData,
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusSection(context),
                const SizedBox(height: 24),
                _buildStatsGrid(),
                const SizedBox(height: 24),
                _buildDailyTipCard(),
                const SizedBox(height: 24),
                const Text('Quick Actions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _buildQuickActions(),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Threat Activity',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    TextButton(
                      onPressed: () {},
                      child: const Text('VIEW ALL >',
                          style: TextStyle(color: AppColors.primary, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildThreatActivity(),
                const SizedBox(height: 24),
                _buildUpgradeBanner(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration:
                        const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                const Text('SHIELD ACTIVE',
                    style: TextStyle(
                        color: AppColors.success, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.primary.withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 5),
                  ],
                ),
              ),
              Column(
                children: [
                  const Text('Secure',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  Text('STATUS', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Your device is protected. All scan data is stored securely on-device.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search, color: Colors.black),
                  SizedBox(width: 8),
                  Text('SCAN NOW',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    final stats = _stats;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: 1.6,
      children: [
        _buildStatCard(
            'TOTAL SCANS',
            _isLoading ? '—' : '${stats?.totalScans ?? 0}',
            Icons.history_outlined),
        _buildStatCard(
            'THREATS FOUND',
            _isLoading ? '—' : '${stats?.threatsDetected ?? 0}',
            Icons.warning_amber_rounded,
            valueColor: AppColors.danger),
        _buildStatCard(
            'SAFE SCANS',
            _isLoading ? '—' : '${stats?.safeCount ?? 0}',
            Icons.check_circle_outline,
            valueColor: AppColors.success),
        _buildStatCard(
            'AVG RISK',
            _isLoading ? '—' : '${stats?.averageRiskScore.round() ?? 0}',
            Icons.show_chart,
            valueColor: AppColors.warning),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon,
      {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 9)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? Colors.white)),
        ],
      ),
    );
  }

  Widget _buildDailyTipCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.accent.withOpacity(0.2), AppColors.surface],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Daily Security Tip',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  DailyTips.getTodaysTip(),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildActionIcon(Icons.sd_card, 'SIM LOCK'),
        _buildActionIcon(Icons.email_outlined, 'EMAIL CHECK'),
        _buildActionIcon(Icons.public, 'BREACHES'),
        _buildActionIcon(Icons.lock_clock_outlined, 'SAFE VAULT'),
      ],
    );
  }

  Widget _buildActionIcon(IconData icon, String label) {
    return Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.primary),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildThreatActivity() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_recentThreats.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.success),
            SizedBox(width: 12),
            Text('No threats detected yet.',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return Column(
      children: _recentThreats.map((r) {
        final isScam = r.classification == 'scam';
        final color = isScam ? AppColors.danger : AppColors.warning;
        final icon = isScam ? Icons.cancel : Icons.warning_amber_outlined;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.classification.toUpperCase(),
                          style: TextStyle(
                              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                      Text(
                        r.inputText.length > 45
                            ? '${r.inputText.substring(0, 45)}...'
                            : r.inputText,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Text(
                  _relativeTime(r.timestamp),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildUpgradeBanner() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [AppColors.accent.withOpacity(0.7), AppColors.background]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Upgrade to Pro',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Unlock Gemini AI-powered analysis with detailed risk breakdowns.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('EXPLORE PLANS', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
