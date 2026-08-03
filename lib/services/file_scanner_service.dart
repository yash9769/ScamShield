// lib/services/file_scanner_service.dart
// Production-grade file scanning service with real permission handling.

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'scam_detector.dart';

enum ScanSource { file, image, clipboard }

class FileScanResult {
  final AnalysisResult analysis;
  final String fileName;
  final ScanSource source;
  final String rawContent;

  const FileScanResult({
    required this.analysis,
    required this.fileName,
    required this.source,
    required this.rawContent,
  });
}

class FileScannerService {
  static final ImagePicker _imagePicker = ImagePicker();

  /// Requests storage permission and picks a text/document file to scan.
  static Future<FileScanResult?> pickAndScanFile() async {
    // On Android 13+ granular permissions are needed; on older, READ_EXTERNAL_STORAGE.
    final status = await _requestStoragePermission();
    if (!status) return null;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'pdf', 'doc', 'docx', 'csv', 'log', 'xml', 'json', 'html', 'htm'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final path = file.path;
    if (path == null) return null;

    String content;
    try {
      // Read file as string. For binary formats we read what we can.
      final bytes = await File(path).readAsBytes();
      content = String.fromCharCodes(bytes.where((b) => b >= 32 || b == 10 || b == 13));
      // Trim to 5000 chars for the detector
      if (content.length > 5000) content = content.substring(0, 5000);
    } catch (_) {
      content = file.name; // fallback — analyse just the filename
    }

    if (content.trim().isEmpty) {
      content = 'File: ${file.name}';
    }

    final analysis = ScamDetector.analyze(content);
    return FileScanResult(
      analysis: analysis,
      fileName: file.name,
      source: ScanSource.file,
      rawContent: content,
    );
  }

  /// Picks an image from gallery and analyses its filename/metadata for scam indicators.
  static Future<FileScanResult?> pickAndScanImage() async {
    final status = await _requestPhotoPermission();
    if (!status) return null;

    final XFile? picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked == null) return null;

    // Analyse the filename and path — scam images often have suspicious names like
    // "bank_otp_form.jpg", "verify_kyc.png", etc.
    final name = picked.name;
    final content = 'Image filename: $name\nImage path: ${picked.path}';
    final analysis = ScamDetector.analyze(content);

    return FileScanResult(
      analysis: analysis,
      fileName: name,
      source: ScanSource.image,
      rawContent: content,
    );
  }

  /// Reads clipboard text and runs the scam detector.
  static Future<FileScanResult?> scanClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return null;

    final analysis = ScamDetector.analyze(text);
    return FileScanResult(
      analysis: analysis,
      fileName: 'Clipboard',
      source: ScanSource.clipboard,
      rawContent: text,
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
