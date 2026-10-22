// lib/screens/qr_result_screen.dart
//
// "Where does this QR code lead?" Shown after a scan and before anything is
// opened. Previously the decoded string was simply dropped into the message
// box, so the person never saw the real address, only a verdict.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../services/osint_service.dart';
import '../services/qr_content.dart';
import '../theme.dart';

/// What the person chose to do with the code.
enum QrAction { analyze, close }

class QrResultScreen extends StatefulWidget {
  final String raw;
  const QrResultScreen({super.key, required this.raw});

  @override
  State<QrResultScreen> createState() => _QrResultScreenState();
}

class _QrResultScreenState extends State<QrResultScreen> {
  late final QrContent _content = QrContentParser.parse(widget.raw);

  List<Uri>? _hops;
  String? _traceError;
  bool _tracing = false;

  List<OsintResult>? _reputation;
  bool _checking = false;

  Color _levelColor(QrWarningLevel l) => switch (l) {
    QrWarningLevel.danger => AppColors.danger,
    QrWarningLevel.caution => AppColors.warning,
    QrWarningLevel.info => AppColors.textSecondary,
  };

  IconData _levelIcon(QrWarningLevel l) => switch (l) {
    QrWarningLevel.danger => Icons.dangerous_outlined,
    QrWarningLevel.caution => Icons.warning_amber_rounded,
    QrWarningLevel.info => Icons.info_outline,
  };

  /// Follows redirects one hop at a time without downloading page bodies, so
  /// the final destination of a shortened link is visible. This DOES contact the
  /// site (and every hop), which is why it is a button and not automatic.
  Future<void> _trace() async {
    final start = _content.uri;
    if (start == null) return;
    setState(() {
      _tracing = true;
      _traceError = null;
      _hops = null;
    });
    final hops = <Uri>[start];
    final client = http.Client();
    try {
      var current = start;
      for (var i = 0; i < 8; i++) {
        final request = http.Request('GET', current)
          ..followRedirects = false
          ..headers['User-Agent'] =
              'Mozilla/5.0 (Linux; Android 14) ScamShield-LinkCheck';
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 8));
        // Never read the body: only the redirect headers matter.
        final location = response.headers['location'];
        final isRedirect =
            response.statusCode >= 300 && response.statusCode < 400;
        await response.stream.listen((_) {}).cancel();
        if (!isRedirect || location == null) break;
        current = current.resolve(location);
        hops.add(current);
      }
      if (mounted) setState(() => _hops = hops);
    } catch (_) {
      if (mounted) {
        setState(() {
          _hops = hops.length > 1 ? hops : null;
          _traceError = hops.length > 1
              ? 'Stopped following the link part-way: the next site did not answer.'
              : 'Could not reach the site to trace it. It may be down, or your connection is offline.';
        });
      }
    } finally {
      client.close();
      if (mounted) setState(() => _tracing = false);
    }
  }

  Future<void> _checkReputation() async {
    final urls = <String>{
      _content.uri.toString(),
      ...?_hops?.map((u) => u.toString()),
    }.toList();
    setState(() => _checking = true);
    final results = await OsintService.checkUrlsGoogleSafeBrowsing(urls);
    if (mounted) {
      setState(() {
        _reputation = results;
        _checking = false;
      });
    }
  }

  Future<void> _open() async {
    final target = _hops?.last ?? _content.uri;
    if (target == null) return;
    if (_content.hasDanger) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Open it anyway?'),
          content: const Text(
            'This link has warning signs that are typical of scams. Opening it '
            'is safer than entering anything on it, but the safest choice is to '
            'not open it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Don\'t open'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Open anyway',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    await launchUrl(target, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = _content;
    return Scaffold(
      appBar: AppBar(title: const Text('What this QR code holds')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          Row(
            children: [
              Icon(
                c.hasDanger ? Icons.dangerous_outlined : Icons.qr_code_2,
                color: c.hasDanger ? AppColors.danger : AppColors.primary,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(
                c.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Nothing has been opened yet.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          for (final f in c.fields)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.key.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    f.value,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: f.key == 'Website owner'
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          if (c.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final w in c.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _levelIcon(w.level),
                      size: 18,
                      color: _levelColor(w.level),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        w.message,
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
          ] else if (c.isLink)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'No obvious disguise tricks in the address. That does not make '
                'the site safe: check the owner above is who you expect.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          if (c.isLink) ...[
            const SizedBox(height: 8),
            const Text(
              'GO FURTHER',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _tracing ? null : _trace,
              icon: _tracing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.alt_route, size: 18),
              label: const Text('Trace where it redirects'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'This contacts the site (without opening it) to follow redirects.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                ),
              ),
            ),
            if (_hops != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _hops!.length == 1
                          ? 'No redirects. It opens this address directly.'
                          : 'Ends up at (${_hops!.length - 1} redirect${_hops!.length == 2 ? '' : 's'}):',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    for (var i = 0; i < _hops!.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: SelectableText(
                          '${i == 0 ? 'Start' : '→'}  ${_hops![i]}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: i == _hops!.length - 1
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    if (_hops!.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Final site owner: ${QrContentParser.registrableDomainOf(_hops!.last.host)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (_traceError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _traceError!,
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 12.5,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _checking ? null : _checkReputation,
              icon: _checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.shield_outlined, size: 18),
              label: const Text('Check against threat lists'),
            ),
            if (_reputation != null)
              for (final r in _reputation!)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        !r.available
                            ? Icons.help_outline
                            : r.isMalicious
                            ? Icons.dangerous_outlined
                            : Icons.check_circle_outline,
                        size: 18,
                        color: !r.available
                            ? AppColors.textSecondary
                            : r.isMalicious
                            ? AppColors.danger
                            : AppColors.success,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${r.provider}: ${r.available ? r.details : 'unavailable right now (check Profile > Server address)'}',
                          style: const TextStyle(fontSize: 12.5, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
          const SizedBox(height: 20),
          if (c.isLink)
            ElevatedButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(
                _hops != null && _hops!.length > 1
                    ? 'Open final site'
                    : 'Open link',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.hasDanger
                    ? AppColors.surfaceLight
                    : AppColors.primary,
                foregroundColor: c.hasDanger ? AppColors.danger : Colors.black,
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, QrAction.analyze),
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Run a full scan on this'),
          ),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: c.raw));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 1),
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy contents'),
          ),
        ],
      ),
    );
  }
}
