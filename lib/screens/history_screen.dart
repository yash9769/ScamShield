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
import '../widgets/ui_kit.dart';

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
                  Icon(verdictStyleFor(record.classification).icon,
                      color: badgeColor, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    verdictStyleFor(record.classification).label,
                    style: AppText.heading.copyWith(color: badgeColor),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${record.source ?? 'Unknown source'} · ${record.timestamp.toString().substring(0, 16)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 16),
              Text('Message', style: AppText.label),
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
              Text('What we found', style: AppText.label),
              const SizedBox(height: 6),
              Text(record.summary,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary, height: 1.4)),
              if (indicators.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Links and numbers in it', style: AppText.label),
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
            : const Text('History'),
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

  /// Filters, as a quiet segmented row.
  ///
  /// Was three ChoiceChips labelled "All Logs (12)", "Threats Only", "Safe
  /// Only" — "Logs" is what an engineer calls this, not a person, and baking
  /// the count into the label made the control resize as the list changed.
  Widget _buildFilterChips() {
    const labels = ['All', 'Threats', 'Safe'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.md,
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.surfaceLight),
        ),
        child: Row(
          children: List.generate(labels.length, (i) {
            final sel = _selectedFilterIndex == i;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedFilterIndex = i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  curve: AppMotion.curve,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.surfaceLight : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: sel ? AppColors.textPrimary : AppColors.textSecondary,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
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
          padding: const EdgeInsets.all(AppSpacing.screen),
          child: EmptyState(
            icon: _allRecords.isEmpty ? Icons.inbox_outlined : Icons.search_off_rounded,
            title: _allRecords.isEmpty ? 'Nothing checked yet' : 'No matches',
            message: _allRecords.isEmpty
                ? 'Everything you check gets saved here, so you can find it again '
                    'or turn it into a complaint later.'
                : 'Nothing here matches that search or filter.',
            actionLabel: _allRecords.isEmpty ? 'Check something now' : null,
            onAction: _allRecords.isEmpty
                ? () => ScanNowBottomSheet.show(context)
                : null,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen, 0, AppSpacing.screen, 96,
      ),
      itemCount: records.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (ctx, index) {
        final r = records[index];
        final v = verdictStyleFor(r.classification);

        final diff = DateTime.now().difference(r.timestamp);
        final timeStr = diff.inMinutes < 1
            ? 'Just now'
            : diff.inHours < 1
                ? '${diff.inMinutes}m ago'
                : diff.inDays < 1
                    ? '${diff.inHours}h ago'
                    : '${diff.inDays}d ago';

        return Reveal(
          delay: Reveal.step(index, stepMs: 35),
          offsetY: 12,
          child: Dismissible(
            key: Key('record_${r.id ?? index}'),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => _deleteRecord(r),
            background: Container(
              padding: const EdgeInsets.only(right: AppSpacing.xl),
              alignment: Alignment.centerRight,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.danger, size: 22),
            ),
            child: AppCard(
              onTap: () => _showRecordDetail(r),
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      VerdictBadge(r.classification, compact: true),
                      const Spacer(),
                      Text(timeStr, style: AppText.caption),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // The message itself is the thing people scan the list for —
                  // it leads, rather than sitting third under a repeated
                  // ALL-CAPS verdict word and a coloured icon tile.
                  Text(
                    r.inputText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body,
                  ),
                  if (r.source != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Icon(_sourceIcon(r.source!),
                            size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 5),
                        Text(r.source!, style: AppText.caption),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _sourceIcon(String source) {
    final s = source.toLowerCase();
    if (s.startsWith('sms')) return Icons.chat_bubble_outline_rounded;
    if (s.contains('link')) return Icons.link_rounded;
    if (s.contains('shared')) return Icons.ios_share_rounded;
    if (s.contains('image')) return Icons.image_outlined;
    if (s.contains('simple')) return Icons.accessibility_new_rounded;
    return Icons.edit_outlined;
  }
}
