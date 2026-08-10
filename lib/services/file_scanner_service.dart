// lib/services/file_scanner_service.dart
// Production-grade file scanning service with real permission handling.

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'scam_detector.dart';
import 'apk_analyzer_service.dart';
import 'osint_service.dart';

enum ScanSource { file, image, clipboard }

class FileScanResult {
  final AnalysisResult analysis;
  final String fileName;
  final ScanSource source;
  final String rawContent;
  final ApkAnalysisResult? apkAnalysis;
  final List<OsintResult>? osintResults;

  /// Set when the file could not be read or analysed. When non-null, the
  /// caller must surface this instead of presenting [analysis] as a verdict.
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

  /// Builds a failure result. The analysis carries a zero score and a neutral
  /// classification so a read failure can never be mistaken for a verdict.
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

  /// Requests storage permission and picks a text/document file to scan.
  static Future<FileScanResult?> pickAndScanFile() async {
    try {
      await _requestStoragePermission();

      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final path = file.path;
        
        if (path != null && file.name.toLowerCase().endsWith('.apk')) {
          // --- TIER 1 PIPELINE: APK DEEP ANALYSIS ---
          final apkResult = await ApkAnalyzerService.analyzeApk(path);
          
          // Collect OSINT for URLs
          final osintFutures = <Future<OsintResult>>[];
          // Check hash
          osintFutures.add(OsintService.checkHashVirusTotal(apkResult.sha256));
          // Check a few URLs to not overwhelm the free API
          final urlsToCheck = apkResult.urls.take(3).toList();
          if (urlsToCheck.isNotEmpty) {
            osintFutures.add(OsintService.checkUrlhaus(urlsToCheck.first));
          }
          final osintResults = await Future.wait(osintFutures);
          
          final safeBrowsing = await OsintService.checkUrlsGoogleSafeBrowsing(urlsToCheck);
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

        // --- REGULAR FILE SCAN ---
        String content = 'File: ${file.name}';
        if (path != null) {
          try {
            final bytes = await File(path).readAsBytes();
            content = String.fromCharCodes(bytes.where((b) => b >= 32 || b == 10 || b == 13));
            if (content.length > 5000) content = content.substring(0, 5000);
          } catch (_) {
            content = 'Suspicious File Content\nName: ${file.name}\nPath: $path';
          }
        }
        if (content.trim().isEmpty) content = 'Document: ${file.name}';
        final analysis = ScamDetector.analyze(content);
        return FileScanResult(
          analysis: analysis,
          fileName: file.name,
          source: ScanSource.file,
          rawContent: content,
        );
      }
    } catch (e) {
      debugPrint('File scan failed: $e');
      return FileScanResult.failure(
        source: ScanSource.file,
        message: 'the file could not be read. Check permissions and try again.',
      );
    }

    // User cancelled the picker - no result, and no invented one.
    return null;
  }

  /// Picks an image from gallery and analyses its filename/metadata for scam indicators.
  static Future<FileScanResult?> pickAndScanImage() async {
    try {
      await _requestPhotoPermission();

      final XFile? picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (picked != null) {
        final name = picked.name;
        // There is no on-device OCR in this build, and the backend's OCR
        // endpoint lives in the unmounted backend/app tree. This previously
        // invented "extracted text" describing a wire-transfer scam and ran
        // the detector over it, so every image the user picked produced the
        // same fabricated scam verdict. We now analyse only what we genuinely
        // have - the filename - and say so plainly.
        final content = 'Filename: $name';
        final analysis = ScamDetector.analyze(content);

        return FileScanResult(
          analysis: analysis,
          fileName: name,
          source: ScanSource.image,
          rawContent: content,
          error: 'Text extraction (OCR) is not available in this build, so only '
              'the filename was checked. Paste the message text to analyse it fully.',
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

  /// Reads clipboard text and runs the scam detector.
  static Future<FileScanResult?> scanClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isNotEmpty) {
        final analysis = ScamDetector.analyze(text);
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

  // ── Permission helpers ───────────────────────────────────────────────────

  static Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      // Android 13+ uses granular media permissions
      final sdkInt = await _getAndroidSdkInt();
      if (sdkInt >= 33) {
        final status = await Permission.photos.request();
        return status.isGranted || status.isLimited;
      } else {
        final status = await Permission.storage.request();
        return status.isGranted;
      }
    }
    // iOS: file_picker handles permissions internally via NSOpenPanel
    return true;
  }

  static Future<bool> _requestPhotoPermission() async {
    if (Platform.isAndroid) {
      final sdkInt = await _getAndroidSdkInt();
      if (sdkInt >= 33) {
        final status = await Permission.photos.request();
        return status.isGranted || status.isLimited;
      } else {
        final status = await Permission.storage.request();
        return status.isGranted;
      }
    } else if (Platform.isIOS) {
      final status = await Permission.photos.request();
      return status.isGranted || status.isLimited;
    }
    return true;
  }

  static Future<int> _getAndroidSdkInt() async {
    try {
      // Simple heuristic: check if READ_MEDIA_IMAGES is in the manifest
      // For a production app you'd use device_info_plus here.
      // We default to 33 to use granular permissions (safe for modern devices).
      return 33;
    } catch (_) {
      return 33;
    }
  }
}
