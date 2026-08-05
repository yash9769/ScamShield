import 'dart:async';

import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/scan_now_bottom_sheet.dart';
import '../data/repositories/scan_repository.dart';
import '../data/models/scan_record.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  final ScanRepository _repo = ScanRepository();
  final TextEditingController _searchController = TextEditingController();

  List<ScanRecord> _records = [];
  ScanStatistics? _stats;
  bool _isLoading = true;
  bool _isSearching = false;

  // 0 = All Scans, 1 = Threats Only, 2 = Safe Scans
  int _selectedFilterIndex = 0;
  Timer? _searchDebounce;

  /// Public hook so the shell can reload data when the tab is opened.
  void refresh() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final query = _searchController.text.trim();
    final records = query.isEmpty
        ? await _repo.loadHistory()
        : await _repo.searchScans(query);
    final stats = await _repo.getStatistics();
    if (mounted) {
      setState(() {
        _records = records;
        _stats = stats;
        _isLoading = false;
      });
    }
  }

  List<ScanRecord> get _filteredRecords {
    return _records.where((r) {
      if (_selectedFilterIndex == 1 && !r.isFlagged &&
          r.classification != 'suspicious') {
        return false;
      }
      if (_selectedFilterIndex == 2 && r.classification != 'safe') {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _deleteRecord(ScanRecord record) async {
    final id = record.id;
    if (id == null) return;
    setState(() => _records.removeWhere((r) => r.id == record.id));
    await _repo.deleteScan(id);
    await _load();
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear Scan History?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'This will permanently delete all saved scan records from this device. This cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _repo.clearHistory();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scan history cleared.'),
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showItemDetails(ScanRecord record) {
    final (tag, color, icon) = _recordStyle(record);    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(icon, color: color, size: 28),
                  const SizedBox(width: 12),
                  Text(_recordTitle(record), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(tag, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const SizedBox(height: 16),
              const Text('Scanned Content / Context:', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 6),
              Text(record.inputText, style: const TextStyle(fontSize: 14, height: 1.5)),
              const SizedBox(height: 16),
              const Text('Analysis Summary:', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 6),
              Text(record.summary, style: const TextStyle(fontSize: 14, height: 1.5)),
              const SizedBox(height: 16),
              Text('Source: ${record.source ?? 'Manual'}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 4),
              Text('Risk Score: ${record.riskScore}/100', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 4),
              Text('Timestamp: ${_formatTime(record.timestamp)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Close Details', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  (String, Color, IconData) _recordStyle(ScanRecord record) {
    switch (record.classification) {
      case 'scam':
        return ('SCAM DETECTED', AppColors.danger, Icons.error_outline);
      case 'suspicious':
        return ('SUSPICIOUS', AppColors.warning, Icons.help_outline_rounded);
      default:
        return ('SAFE SCAN', AppColors.success, Icons.check_circle_outline);
    }
  }

  String _recordTitle(ScanRecord record) {
    switch (record.classification) {
      case 'scam':
        return 'Scam Detected';
      case 'suspicious':
        return 'Suspicious Content';
      default:
        return 'Safe Content';
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final diff = today.difference(day).inDays;
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    if (diff == 0) return 'Today, $hh:$mm';
    if (diff == 1) return 'Yesterday, $hh:$mm';
    return '${time.month}/${time.day}/${time.year}, $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search scan logs...',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) {
                  _searchDebounce?.cancel();
                  _load();
                },
                onChanged: (_) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(const Duration(milliseconds: 300), _load);
                },
              )
            : const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('History', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  Text('Review your recent scans and security alerts.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _load();
                }
              });
            },
          ),
          if (_records.isNotEmpty && !_isSearching)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.danger),
              tooltip: 'Clear history',
              onPressed: _clearHistory,
            ),
          const SizedBox(width: 8),
        ],
        toolbarHeight: 90,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: _isLoading && _records.isEmpty
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 4,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text('Loading your scans...',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildFilterChips(),
                  const SizedBox(height: 24),
                  if (_filteredRecords.isEmpty)
                    _buildEmptyState()
                  else
                    ..._filteredRecords.map((record) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildHistoryItem(record),
                        )),
                  const SizedBox(height: 24),
                  if (_stats != null) _buildWeeklyProtectionCard(_stats!),
                  const SizedBox(height: 80),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ScanNowBottomSheet.show(context),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.qr_code_scanner, color: Colors.black),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.25),
              ),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: AppColors.primary,
              size: 40,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No scans yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your scanned links and QR codes\nwill appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => ScanNowBottomSheet.show(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Start Scanning'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Row(
      children: [
        _buildChip('All Scans', 0),
        const SizedBox(width: 8),
        _buildChip('Threats Only', 1),
        const SizedBox(width: 8),
        _buildChip('Safe Scans', 2),
      ],
    );
  }

  Widget _buildChip(String label, int index) {
    final isSelected = _selectedFilterIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilterIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.textSecondary.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryItem(ScanRecord record) {
    final (tag, color, icon) = _recordStyle(record);
    return Dismissible(
      key: ValueKey('scan-${record.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.danger),
      ),
      onDismissed: (_) => _deleteRecord(record),
      child: InkWell(
        onTap: () => _showItemDetails(record),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2)),
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
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        Text(tag, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Text(_formatTime(record.timestamp), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _recordTitle(record),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text('${record.riskScore}', style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                record.inputText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Divider(color: AppColors.textSecondary, height: 1),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(record.source ?? 'Manual', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyProtectionCard(ScanStatistics stats) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surface, AppColors.accent.withValues(alpha: 0.1)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Scan Statistics', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Real-time stats across all your saved scans.', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStat('${stats.threatsDetected}', 'THREATS', AppColors.primary),
              _buildStat('${stats.safeCount}', 'VERIFIED', AppColors.success),
              _buildStat('${stats.totalScans}', 'TOTAL SCANS', Colors.white),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String value, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }
}
