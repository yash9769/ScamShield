import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../theme.dart';
import '../widgets/scan_now_bottom_sheet.dart';
import '../widgets/motion.dart';
import '../data/models/scan_record.dart';
import '../data/repositories/scan_repository.dart';
import '../services/data_change_notifier.dart';
import '../services/report_generator_service.dart';
import '../services/cloud_sync_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ScanRepository _repo = ScanRepository();

  int _selectedFilterIndex = 0; // 0=All 1=Threats 2=Safe
  bool _isSearching = false;
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  List<ScanRecord> _allRecords = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _searchController.addListener(() => setState(() {}));
    // MainNavigation keeps this screen alive in an IndexedStack, so a
    // deletion made elsewhere (e.g. Settings > Privacy & Data) would
    // otherwise leave this list showing already-deleted records until the
    // user manually swipes/clears. See data_change_notifier.dart.
    DataChangeNotifier.version.addListener(_loadHistory);
  }

  @override
  void dispose() {
    DataChangeNotifier.version.removeListener(_loadHistory);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final records = await _repo.loadHistory();
      if (mounted) setState(() { _allRecords = records; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<ScanRecord> get _filteredRecords {
    final query = _searchController.text.trim().toLowerCase();
    return _allRecords.where((r) {
      if (_selectedFilterIndex == 1 && r.classification.toLowerCase() == 'safe') return false;
      if (_selectedFilterIndex == 2 && r.classification.toLowerCase() != 'safe') return false;
      if (query.isNotEmpty) {
        return r.inputText.toLowerCase().contains(query) ||
               (r.summary.toLowerCase().contains(query)) ||
               (r.source?.toLowerCase().contains(query) ?? false);
      }
      return true;
    }).toList();
  }

  /// Builds the complaint evidence pack for a saved scan and opens it, so the
  /// user can attach it to a cybercrime.gov.in filing or a bank dispute.
  Future<void> _exportComplaint(ScanRecord record) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Preparing complaint evidence…'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );
    try {
      final file = await ReportGeneratorService.generateComplaintReport(record: record);
      await OpenFilex.open(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not create the complaint PDF: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showRecordDetail(ScanRecord record) {
    final badgeColor = record.classification.toLowerCase() == 'scam'
        ? AppColors.danger
        : record.classification.toLowerCase() == 'suspicious'
            ? AppColors.warning
            : AppColors.success;
    final indicators = ReportGeneratorService.extractIndicators(record.inputText);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    record.classification.toUpperCase(),
                    style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  Text(
                    '${record.riskScore}/100',
                    style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${record.source ?? 'Unknown source'} · ${record.timestamp.toString().substring(0, 16)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 16),
              const Text('MESSAGE',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  record.inputText,
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.4),
                ),
              ),
              const SizedBox(height: 16),
              const Text('SUMMARY',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1)),
              const SizedBox(height: 6),
              Text(record.summary,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary, height: 1.4)),
              if (indicators.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('EXTRACTED INDICATORS',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 1)),
                const SizedBox(height: 6),
                ...indicators.map((i) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${i.type}: ',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          Expanded(
                            child: SelectableText(
                              i.value,
                              style: const TextStyle(fontSize: 12, color: AppColors.warning),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _exportComplaint(record);
                  },
                  icon: const Icon(Icons.gavel_outlined, size: 18, color: Colors.black),
                  label: const Text('Export complaint evidence (PDF)',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Creates a PDF with the message, timestamp and extracted links/numbers, '
                'ready to attach to a cybercrime.gov.in complaint or a bank dispute.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteRecord(ScanRecord record) async {
    if (record.id == null) return;
    await _repo.deleteById(record.id!);
    // If this scan was ever pushed to the server via cross-device sync, it
    // is still sitting there untouched — a plain local delete never tells
    // the server anything changed. A no-op when signed out or unsynced.
    unawaited(CloudSyncService.pushTombstones([record]));
    await _loadHistory();
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Text("Clear All Scan Data?", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          "This will reset all scan history to 0 and permanently delete local SQLite records.",
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text("Reset All to 0", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // Captured before clearing: once the rows are gone locally, there is
      // nothing left to compute their cloud ids from.
      final toTombstone = _allRecords;
      await _repo.clearAll();
      unawaited(CloudSyncService.pushTombstones(toTombstone));
      await _loadHistory();
    }
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
                  hintText: 'Search history...',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  border: InputBorder.none,
                ),
              )
            : const Text('Scan History & Logs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: AppColors.textPrimary),
            onPressed: () => setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) _searchController.clear();
            }),
          ),
          if (_allRecords.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.danger),
              onPressed: _clearAll,
              tooltip: 'Reset All Data',
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildFilterChips(),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ScanNowBottomSheet.show(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.shield_outlined),
        label: const Text("NEW SCAN", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ),
    );
  }

  Widget _buildFilterChips() {
    final labels = ["All Logs (${_allRecords.length})", "Threats Only", "Safe Only"];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: List.generate(labels.length, (i) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(labels[i]),
            selected: _selectedFilterIndex == i,
            selectedColor: AppColors.primary,
            backgroundColor: AppColors.surface,
            onSelected: (_) => setState(() => _selectedFilterIndex = i),
            labelStyle: TextStyle(
              color: _selectedFilterIndex == i ? Colors.black : AppColors.textSecondary,
              fontWeight: _selectedFilterIndex == i ? FontWeight.bold : FontWeight.w500,
              fontSize: 12,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        )),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    final records = _filteredRecords;
    if (records.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
                ),
                child: const Icon(Icons.inbox_outlined, size: 54, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              const Text('No Scan Records Found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                _allRecords.isEmpty
                    ? 'Scan history is currently clean (0 scans recorded).'
                    : 'No records match your active search or filter.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: records.length,
      itemBuilder: (ctx, index) {
        final r = records[index];
        final Color badgeColor;
        final IconData badgeIcon;
        switch (r.classification.toLowerCase()) {
          case 'scam':
            badgeColor = AppColors.danger;
            badgeIcon = Icons.error_outline;
            break;
          case 'suspicious':
            badgeColor = AppColors.warning;
            badgeIcon = Icons.warning_amber_outlined;
            break;
          default:
            badgeColor = AppColors.success;
            badgeIcon = Icons.check_circle_outline;
        }

        final diff = DateTime.now().difference(r.timestamp);
        final timeStr = diff.inMinutes < 1 ? 'Just now'
            : diff.inHours < 1 ? '${diff.inMinutes}m ago'
            : diff.inDays < 1 ? '${diff.inHours}h ago'
            : '${diff.inDays}d ago';

        return Reveal(
          delay: Reveal.step(index, stepMs: 45),
          offsetY: 16,
          child: Dismissible(
          key: Key('record_${r.id ?? index}'),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => _deleteRecord(r),
          background: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.only(right: 20),
            alignment: Alignment.centerRight,
            decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          child: InkWell(
            onTap: () => _showRecordDetail(r),
            borderRadius: BorderRadius.circular(18),
            child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                  child: Icon(badgeIcon, color: badgeColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(r.classification.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: badgeColor, fontSize: 13)),
                          Text(timeStr, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r.inputText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        r.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ),
        ),
        );
      },
    );
  }
}
