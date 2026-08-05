// lib/screens/batch_scan_screen.dart
// Batch scam scanning: pastes up to 20 messages (one per line) and analyses
// them all in parallel via POST /analyze-batch.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/scam_detector.dart';
import '../widgets/analysis_result_view.dart';

class BatchScanScreen extends StatefulWidget {
  const BatchScanScreen({super.key});

  @override
  State<BatchScanScreen> createState() => _BatchScanScreenState();
}

class _BatchScanScreenState extends State<BatchScanScreen> {
  static const int _maxItems = 20;

  final TextEditingController _controller = TextEditingController();
  bool _isScanning = false;
  BatchScanResult? _result;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> _parseItems() {
    return _controller.text
        .split(RegExp(r'\r?\n+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<void> _scan() async {
    final items = _parseItems();
    if (items.isEmpty) {
      _showSnack('Enter at least one message.', isError: true);
      return;
    }
    if (items.length > _maxItems) {
      _showSnack('Maximum $_maxItems messages per batch.', isError: true);
      return;
    }

    setState(() {
      _isScanning = true;
      _result = null;
      _error = null;
    });

    try {
      final result = await ApiService.analyzeBatch(items);
      if (mounted) {
        setState(() {
          _result = result;
          _isScanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _error = e.toString();
        });
      }
    }
  }

  void _showSnack(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : AppColors.surface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _loadSamples() {
    _controller.text = [
      'Dear customer, your bank account has been locked. Verify immediately: http://sbi-verify.xyz',
      'Hi! We haven\'t talked in a while. Can we connect on LinkedIn?',
      'CONGRATULATIONS! You have won Rs 10,00,000. Click here to claim now!',
      'Your OTP for the transaction is 482913. Never share it with anyone.',
      'Meeting rescheduled to 3 PM tomorrow. Please confirm availability.',
    ].join('\n');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = _parseItems();
    final overLimit = items.length > _maxItems;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/icon.png', height: 28, width: 28,
                errorBuilder: (c, e, s) =>
                    const Icon(Icons.library_books, color: AppColors.primary)),
            const SizedBox(width: 8),
            const Text('Batch Scanner'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Paste up to $_maxItems messages, one per line. Each message is analysed '
              'in parallel by the AI engine.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 16),

            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _controller,
                    maxLines: 10,
                    minLines: 6,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 13, height: 1.5),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.all(16),
                      hintText: 'Message 1\nMessage 2\nMessage 3\n...',
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.15),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          overLimit
                              ? '${items.length}/$_maxItems — too many!'
                              : '${items.length}/$_maxItems messages',
                          style: TextStyle(
                            color: overLimit ? AppColors.danger : AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: overLimit ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        TextButton(
                          onPressed: _loadSamples,
                          child: const Text('Load samples',
                              style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: items.isEmpty || overLimit || _isScanning ? null : _scan,
              icon: const Icon(Icons.bolt_outlined),
              label: Text(_isScanning ? 'Analyzing Batch...' : 'Analyze All (${items.length})'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
            const SizedBox(height: 20),

            if (_isScanning) ...[
              const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              const SizedBox(height: 12),
              const Center(
                child: Text('Running parallel AI analysis...', style: TextStyle(color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 20),
            ],

            if (_error != null)
              Text('Error: $_error', style: const TextStyle(color: AppColors.danger, fontSize: 13)),

            if (_result != null && !_isScanning) ...[
              _buildSummary(_result!),
              const SizedBox(height: 16),
              _buildResults(_result!),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(BatchScanResult result) {
    final allSafe = result.failed == 0 &&
        result.results.every((r) => r.result?.classification == ScamClassification.safe);
    final Color color = allSafe ? AppColors.success : AppColors.danger;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(allSafe ? Icons.verified_outlined : Icons.warning_amber_rounded, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allSafe ? 'Batch looks clean' : 'Threats detected in batch',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  '${result.processed} analysed · ${result.failed} failed · ${result.total} total',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(BatchScanResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Per-message results', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Tap a message to expand its analysis',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 16),
        ...result.results.map((item) => _buildItemCard(item)),
      ],
    );
  }

  Widget _buildItemCard(BatchItemResult item) {
    final analysis = item.result;
    final (Color color, IconData icon) = switch (analysis?.classification) {
      ScamClassification.scam => (AppColors.danger, Icons.warning_rounded),
      ScamClassification.suspicious => (AppColors.warning, Icons.help_outline_rounded),
      _ => (AppColors.success, Icons.check_circle_outline_rounded),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(
          item.textPreview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  _classificationLabel(analysis?.classification),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                analysis != null ? '${analysis.riskScore}/100' : 'failed',
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        children: [
          if (item.error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Analysis failed: ${item.error}',
                  style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            )
          else if (analysis != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: AnalysisResultView(result: analysis, showHeader: false),
            )
          else
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No result available', style: TextStyle(color: AppColors.textSecondary)),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _classificationLabel(ScamClassification? classification) {
    return switch (classification) {
      ScamClassification.scam => 'SCAM',
      ScamClassification.suspicious => 'SUSPICIOUS',
      _ => 'SAFE',
    };
  }
}
