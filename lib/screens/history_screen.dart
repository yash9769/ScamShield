// lib/screens/history_screen.dart

import 'package:flutter/material.dart';
import '../theme.dart';
import '../data/models/scan_record.dart';
import '../data/repositories/scan_repository.dart';
import '../widgets/offline_banner.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ScanRepository _repo = ScanRepository();
  final TextEditingController _searchController = TextEditingController();

  List<ScanRecord> _records = [];
  ScanStatistics? _stats;
  String _activeFilter = 'all';
  bool _isLoading = true;
  bool _isSearching = false;

  final List<Map<String, String>> _filters = [
    {'label': 'All Scans', 'value': 'all'},
    {'label': 'Threats', 'value': 'scam'},
    {'label': 'Suspicious', 'value': 'suspicious'},
    {'label': 'Safe', 'value': 'safe'},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final records = await _repo.filterByClassification(_activeFilter);
      final stats = await _repo.getStatistics();
      setState(() {
        _records = records;
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      _loadData();
      return;
    }
    setState(() => _isLoading = true);
    final results = await _repo.searchScans(query);
    setState(() {
      _records = results;
      _isLoading = false;
    });
  }

  Future<void> _deleteRecord(ScanRecord record) async {
    if (record.id == null) return;
    await _repo.deleteScan(record.id!);
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan record deleted'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Clear All History?'),
        content: const Text(
          'This will permanently delete all scan records. This action cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _repo.clearHistory();
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return OfflineBanner(
      child: Scaffold(
        appBar: AppBar(
          title: _isSearching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Search scans...',
                    hintStyle: TextStyle(color: AppColors.textSecondary),
                    border: InputBorder.none,
                  ),
                  onChanged: _search,
                )
              : const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('History', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    Text('Your scan records', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
          toolbarHeight: _isSearching ? kToolbarHeight : 80,
          actions: [
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchController.clear();
                    _loadData();
                  }
                });
              },
            ),
            if (!_isSearching)
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.danger),
                onPressed: _clearAll,
                tooltip: 'Clear All',
              ),
          ],
        ),
        body: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _loadData,
              color: AppColors.primary,
              backgroundColor: AppColors.surface,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildFilterChips(),
                    const SizedBox(height: 16),
                    if (_stats != null) _buildStatsCard(_stats!),
                    const SizedBox(height: 16),
                    if (_isLoading)
                      const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    else if (_records.isEmpty)
                      _buildEmptyState()
                    else
                      ..._records.map((r) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildHistoryItem(r),
                          )),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton(
                onPressed: () {},
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.qr_code_scanner, color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = _filters[i];
          final isSelected = _activeFilter == f['value'];
          return GestureDetector(
            onTap: () {
              setState(() => _activeFilter = f['value']!);
              _loadData();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary.withOpacity(0.3),
                ),
              ),
              child: Text(
                f['label']!,
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatsCard(ScanStatistics stats) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.surface, AppColors.accent.withOpacity(0.1)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatCell('${stats.totalScans}', 'TOTAL', Colors.white),
          _buildStatCell('${stats.threatsDetected}', 'THREATS', AppColors.danger),
          _buildStatCell('${stats.safeCount}', 'SAFE', AppColors.success),
          _buildStatCell('${stats.averageRiskScore.round()}', 'AVG RISK', AppColors.warning),
        ],
      ),
    );
  }

  Widget _buildStatCell(String value, String label, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildHistoryItem(ScanRecord record) {
    final color = _colorForClassification(record.classification);
    final icon = _iconForClassification(record.classification);
    final tag = record.classification.toUpperCase();

    return Dismissible(
      key: Key(record.id?.toString() ?? record.inputText),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _deleteRecord(record),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: AppColors.danger.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.danger),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(tag,
                          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Text(
                  _formatDate(record.timestamp),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    record.inputText.length > 60
                        ? '${record.inputText.substring(0, 60)}...'
                        : record.inputText,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${record.riskScore}',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(record.summary,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            const Divider(color: AppColors.textSecondary, height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Source: ${record.source ?? 'Manual'}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                const Text('Swipe to delete →',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Icon(Icons.history_toggle_off, color: AppColors.textSecondary.withOpacity(0.4), size: 80),
          const SizedBox(height: 16),
          const Text('No scans yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Use the Scan tab to analyse a message.\nYour history will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Color _colorForClassification(String c) {
    switch (c) {
      case 'scam':
        return AppColors.danger;
      case 'suspicious':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  IconData _iconForClassification(String c) {
    switch (c) {
      case 'scam':
        return Icons.error_outline;
      case 'suspicious':
        return Icons.warning_amber_outlined;
      default:
        return Icons.check_circle_outline;
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
