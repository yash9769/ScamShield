// lib/screens/trends_screen.dart
//
// "What's going around" — community scam reports aggregated by category.
//
// This is the retention piece: it gives someone a reason to open ScamShield on
// a day they *haven't* been scammed. It's built from real reports submitted
// through the app rather than a curated editorial feed, so it reflects what
// users are actually hitting this week.
//
// The server returns counts only, never the reported indicators themselves —
// a feed listing live scam numbers would be a directory for the wrong people.

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/motion.dart';
import '../services/cloud_account_service.dart';

class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key});

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  bool _loading = true;
  ScamTrends? _trends;
  int _windowDays = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final trends = await CloudAccountService.fetchTrends(days: _windowDays);
    if (!mounted) return;
    setState(() {
      _trends = trends;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scam Trends')),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Reveal(delay: Reveal.step(0), child: _buildWindowSelector()),
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              )
            else if (_trends == null)
              _buildUnavailable()
            else if (_trends!.trends.isEmpty)
              _buildEmpty()
            else
              ..._buildTrendList(_trends!),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowSelector() {
    return Row(
      children: [
        for (final days in [7, 30, 90]) ...[
          Expanded(
            child: GestureDetector(
              onTap: _loading
                  ? null
                  : () {
                      setState(() => _windowDays = days);
                      _load();
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _windowDays == days ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  days == 7 ? 'This week' : '$days days',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _windowDays == days ? Colors.black : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ),
          if (days != 90) const SizedBox(width: 8),
        ],
      ],
    );
  }

  List<Widget> _buildTrendList(ScamTrends trends) {
    // Bars are scaled against the busiest category rather than the total, so
    // the shape of the week is readable even when one category dominates.
    final maxReports = trends.trends
        .map((t) => t.reports)
        .fold<int>(1, (a, b) => a > b ? a : b);

    return [
      Reveal(
        delay: Reveal.step(1),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.16),
                AppColors.accent.withValues(alpha: 0.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              const Icon(Icons.trending_up, color: AppColors.primary, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${trends.totalReports} reports',
                        style: Theme.of(context).textTheme.headlineSmall),
                    Text(
                      'submitted by the community in the last ${trends.windowDays} days',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 22),
      Reveal(
        delay: Reveal.step(2),
        child: const Text(
          'BY CATEGORY',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0,
          ),
        ),
      ),
      const SizedBox(height: 10),
      ...trends.trends.asMap().entries.map(
            (e) => Reveal(
              delay: Reveal.step(e.key + 3, stepMs: 45),
              child: _buildTrendRow(e.value, maxReports),
            ),
          ),
      const SizedBox(height: 20),
      const Text(
        'Counts come from reports submitted by ScamShield users. The reported '
        'numbers and links themselves are never shown here.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.4),
      ),
    ];
  }

  Widget _buildTrendRow(TrendItem item, int maxReports) {
    final fraction = (item.reports / maxReports).clamp(0.05, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.category,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
              ),
              Text(
                '${item.reports}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: AppColors.background,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${item.distinctIndicators} distinct number(s)/link(s) reported',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        children: [
          Icon(Icons.insights_outlined, color: AppColors.textSecondary, size: 34),
          SizedBox(height: 12),
          Text(
            'No reports in this window yet',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          SizedBox(height: 6),
          Text(
            'When you report a scam link or number, it feeds this trend view for '
            'everyone else too.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildUnavailable() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: const Column(
        children: [
          Icon(Icons.cloud_off, color: AppColors.warning, size: 30),
          SizedBox(height: 12),
          Text('Trends are unavailable',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          SizedBox(height: 6),
          Text(
            'Could not reach the ScamShield service. Pull down to try again — '
            'scanning still works offline.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    );
  }
}
