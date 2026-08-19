// lib/services/file_scanner_service.dart
// Web-compatible file scanning service — uses bytes not dart:io File.

import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'settings_service.dart';
import 'scam_detector.dart';
import 'api_service.dart';
import 'apk_analyzer_service.dart';
import 'osint_service.dart';
import 'file_io_helper.dart'; // conditional dart:io wrapper

export 'apk_analyzer_service.dart';

enum ScanSource { file, image, clipboard }

class FileScanResult {
  final AnalysisResult analysis;
  final String fileName;
  final ScanSource source;
  final String rawContent;
  final ApkAnalysisResult? apkAnalysis;
  final List<OsintResult>? osintResults;

  /// Set when the file could not be read or analysed.
  final String? error;

  const FileScanResult({
    required this.analysis,
    required this.fileName,
    required this.source,
    required this.rawContent,
    this.apkAnalysis,
    this.osintResults,
    this.error,
  });

  bool get hasError => error != null;

  factory FileScanResult.failure({
    required ScanSource source,
    required String message,
    String fileName = 'Unknown',
  }) {
    return FileScanResult(
      analysis: AnalysisResult(
        classification: ScamClassification.safe,
        riskScore: 0,
        reasons: const [],
        status: AnalysisStatus.unavailable,
        summary: 'Not analysed - $message',
      ),
      fileName: fileName,
      source: source,
      rawContent: '',
      error: message,
    );
  }
}

class FileScannerService {
  static final ImagePicker _imagePicker = ImagePicker();

  /// Picks any file and scans it. Web uses bytes; native uses path or bytes.
  static Future<FileScanResult?> pickAndScanFile() async {
    try {
      await _requestStoragePermission();

      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true, // loads bytes on all platforms including web
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final bytes = file.bytes;

        // APK scan — native only
        if (!kIsWeb && file.path != null &&
            file.name.toLowerCase().endsWith('.apk')) {
          return _analyzeApkFile(file);
        }

        // --- Use bytes (works on web + native) ---
        if (bytes != null && bytes.isNotEmpty) {
          if (_isTextExtension(file.name)) {
            // Text file — decode and analyze via backend AI
            String content;
            try {
              content = utf8.decode(bytes, allowMalformed: true);
              if (content.length > 6000) content = content.substring(0, 6000);
            } catch (_) {
              content = String.fromCharCodes(
                  bytes.where((b) => b >= 32 || b == 10 || b == 13));
              if (content.length > 6000) {
                content = content.substring(0, 6000);
              }
            }
            if (content.trim().isEmpty) content = 'Document: ${file.name}';

            AnalysisResult analysis;
            try {
              analysis = await ApiService.analyzeMessage(content);
              if (!analysis.isAnalyzed) {
                analysis = ScamDetector.analyze(content);
              }
            } catch (_) {
              analysis = ScamDetector.analyze(content);
            }
            return FileScanResult(
              analysis: analysis,
              fileName: file.name,
              source: ScanSource.file,
              rawContent: content,
            );
          } else {
            // Binary file (image, pdf) — send to backend OCR
            AnalysisResult analysis;
            try {
              analysis = await ApiService.analyzeFileBytes(
                bytes: bytes,
                filename: file.name,
              );
              if (!analysis.isAnalyzed) {
                analysis = ScamDetector.analyze('Document: ${file.name}');
              }
            } catch (_) {
              analysis = ScamDetector.analyze('Document: ${file.name}');
            }
            return FileScanResult(
              analysis: analysis,
              fileName: file.name,
              source: ScanSource.file,
              rawContent: 'Binary document scanned via OCR: ${file.name}',
            );
          }
        }

        // Native fallback — read via dart:io through helper
        final path = file.path;
        if (path != null && !kIsWeb) {
          return _analyzeNativePath(file.name, path);
        }
      }
    } catch (e) {
      debugPrint('File scan failed: $e');
      return FileScanResult.failure(
        source: ScanSource.file,
        message: 'the file could not be read. Check permissions and try again.',
      );
    }

    return null; // user cancelled
  }

  /// Picks an image from gallery and runs OCR + AI analysis via backend.
  static Future<FileScanResult?> pickAndScanImage() async {
    try {
      await _requestPhotoPermission();

      final XFile? picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        requestFullMetadata: false,
      );

      if (picked != null) {
        final bytes = await picked.readAsBytes();

        AnalysisResult analysis;
        try {
          analysis = await ApiService.analyzeImageXFile(picked);
          if (!analysis.isAnalyzed) {
            analysis = ScamDetector.analyze('Screenshot: ${picked.name}');
          }
        } catch (_) {
          analysis = ScamDetector.analyze('Screenshot: ${picked.name}');
        }

        return FileScanResult(
          analysis: analysis,
          fileName: picked.name,
          source: ScanSource.image,
          rawContent:
              'Image scanned via OCR: ${picked.name} (${bytes.length} bytes)',
        );
      }
    } catch (e) {
      debugPrint('Image scan failed: $e');
      return FileScanResult.failure(
        source: ScanSource.image,
        message: 'the image could not be read. Check permissions and try again.',
      );
    }

    return null;
  }

  /// Reads clipboard text and runs the scam detector + backend AI.
  static Future<FileScanResult?> scanClipboard() async {
    if (!SettingsService.autoScanClipboard.value) {
      return FileScanResult.failure(
        source: ScanSource.clipboard,
        message: 'Clipboard scanning is disabled in settings.',
        fileName: 'Clipboard',
      );
    }
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isNotEmpty) {
        AnalysisResult analysis;
        try {
          analysis = await ApiService.analyzeMessage(text);
          if (!analysis.isAnalyzed) analysis = ScamDetector.analyze(text);
        } catch (_) {
          analysis = ScamDetector.analyze(text);
        }
        return FileScanResult(
          analysis: analysis,
          fileName: 'Clipboard',
          source: ScanSource.clipboard,
          rawContent: text,
        );
      }
    } catch (e) {
      debugPrint('Clipboard scan failed: $e');
      return FileScanResult.failure(
        source: ScanSource.clipboard,
        message: 'the clipboard could not be read.',
        fileName: 'Clipboard',
      );
    }

    return FileScanResult.failure(
      source: ScanSource.clipboard,
      message: 'the clipboard is empty. Copy a message or link first.',
      fileName: 'Clipboard',
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static Future<FileScanResult> _analyzeApkFile(PlatformFile file) async {
    final path = file.path!;
    final apkResult = await ApkAnalyzerService.analyzeApk(path);
    final osintFutures = <Future<OsintResult>>[];
    osintFutures.add(OsintService.checkHashVirusTotal(apkResult.sha256));
    final urlsToCheck = apkResult.urls.take(3).toList();
    if (urlsToCheck.isNotEmpty) {
      osintFutures.add(OsintService.checkUrlhaus(urlsToCheck.first));
    }
    final osintResults = await Future.wait(osintFutures);
    final safeBrowsing =
        await OsintService.checkUrlsGoogleSafeBrowsing(urlsToCheck);
    osintResults.addAll(safeBrowsing);
    final analysis = ScamDetector.analyzeApk(apkResult, osintResults);
    return FileScanResult(
      analysis: analysis,
      fileName: file.name,
      source: ScanSource.file,
      rawContent: 'APK Static Analysis Complete',
      apkAnalysis: apkResult,
      osintResults: osintResults,
    );
  }

  static Future<FileScanResult> _analyzeNativePath(
      String name, String path) async {
    try {
      final bytes = await FileIoHelper.readBytes(path);
      String content = utf8.decode(bytes, allowMalformed: true);
      if (content.length > 6000) content = content.substring(0, 6000);
      if (content.trim().isEmpty) content = 'Document: $name';
      AnalysisResult analysis;
      try {
        analysis = await ApiService.analyzeMessage(content);
        if (!analysis.isAnalyzed) analysis = ScamDetector.analyze(content);
      } catch (_) {
        analysis = ScamDetector.analyze(content);
      }
      return FileScanResult(
        analysis: analysis,
        fileName: name,
        source: ScanSource.file,
        rawContent: content,
      );
    } catch (_) {
      final analysis = ScamDetector.analyze('File: $name');
      return FileScanResult(
        analysis: analysis,
        fileName: name,
        source: ScanSource.file,
        rawContent: 'File: $name',
      );
    }
  }

  static bool _isTextExtension(String name) {
    final ext = name.toLowerCase();
    return ext.endsWith('.txt') ||
        ext.endsWith('.csv') ||
        ext.endsWith('.json') ||
        ext.endsWith('.log') ||
        ext.endsWith('.xml') ||
        ext.endsWith('.html') ||
        ext.endsWith('.htm') ||
        ext.endsWith('.md') ||
        ext.endsWith('.dart') ||
        ext.endsWith('.py') ||
        ext.endsWith('.js');
  }

  // ── Permission helpers ──────────────────────────────────────────────────────

  static Future<bool> _requestStoragePermission() async {
    if (kIsWeb) return true;
    if (FileIoHelper.isAndroid) {
      final sdkInt = await _getAndroidSdkInt();
      if (sdkInt >= 33) {
        final status = await Permission.photos.request();
        return status.isGranted || status.isLimited;
      } else {
        final status = await Permission.storage.request();
        return status.isGranted;
      }
    }
    return true;
  }

  static Future<bool> _requestPhotoPermission() async {
    if (kIsWeb) return true;
    if (FileIoHelper.isAndroid) {
      final sdkInt = await _getAndroidSdkInt();
      if (sdkInt >= 33) {
        final status = await Permission.photos.request();
        return status.isGranted || status.isLimited;
      } else {
        final status = await Permission.storage.request();
        return status.isGranted;
      }
    } else if (FileIoHelper.isIOS) {
      final status = await Permission.photos.request();
      return status.isGranted || status.isLimited;
    }
    return true;
  }

  static Future<int> _getAndroidSdkInt() async {
    return 33; // safe default for modern Android
  }
}
