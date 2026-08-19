import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../widgets/scan_now_bottom_sheet.dart';
import '../widgets/motion.dart';
import '../data/models/scan_record.dart';
import '../data/repositories/scan_repository.dart';

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
  }

  @override
  void dispose() {
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

  Future<void> _deleteRecord(ScanRecord record) async {
    if (record.id == null) return;
    await _repo.deleteById(record.id!);
    await _loadHistory();
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
            const SizedBox(width: 8),
            Text("Clear All Scan Data?", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          "This will reset all scan history to 0 and permanently delete local SQLite records.",
          style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("Cancel", style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text("Reset All to 0", style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _repo.clearAll();
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
                style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search history...',
                  hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.mutedText),
                  border: InputBorder.none,
                ),
              )
            : Text('Scan History & Logs', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 20)),
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
              icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.danger),
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
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton.extended(
          onPressed: () => ScanNowBottomSheet.show(context),
          backgroundColor: AppColors.cobalt,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.shield_outlined),
          label: Text("NEW SCAN", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ),
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
            selectedColor: AppColors.cobalt,
            backgroundColor: AppColors.surface,
            onSelected: (_) => setState(() => _selectedFilterIndex = i),
            labelStyle: GoogleFonts.plusJakartaSans(
              color: _selectedFilterIndex == i ? Colors.white : AppColors.textSecondary,
              fontWeight: _selectedFilterIndex == i ? FontWeight.bold : FontWeight.w500,
              fontSize: 12,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.border),
            ),
          ),
        )),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.cobalt));
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
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.inbox_rounded, size: 48, color: AppColors.mutedText),
              ),
              const SizedBox(height: 20),
              Text('No Scan Records Found', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Text(
                _allRecords.isEmpty
                    ? 'Scan history is clean (0 scans recorded).'
                    : 'No records match your search query.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 90),
      itemCount: records.length,
      itemBuilder: (ctx, index) {
        final r = records[index];
        final Color badgeColor;
        final IconData badgeIcon;
        switch (r.classification.toLowerCase()) {
          case 'scam':
            badgeColor = AppColors.danger;
            badgeIcon = Icons.gpp_bad_rounded;
            break;
          case 'suspicious':
            badgeColor = AppColors.warning;
            badgeIcon = Icons.gpp_maybe_rounded;
            break;
          default:
            badgeColor = AppColors.safeEmerald;
            badgeIcon = Icons.verified_rounded;
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
              decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.delete_rounded, color: Colors.white),
            ),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                    child: Icon(badgeIcon, color: badgeColor, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(r.classification.toUpperCase(), style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, color: badgeColor, fontSize: 12)),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.cobalt.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    r.source ?? 'Manual',
                                    style: GoogleFonts.plusJakartaSans(color: AppColors.cobalt, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            Text(timeStr, style: GoogleFonts.plusJakartaSans(color: AppColors.mutedText, fontSize: 10)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          r.inputText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          r.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 12, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
