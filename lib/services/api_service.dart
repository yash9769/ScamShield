// lib/services/api_service.dart
// HTTP client for the FastAPI backend: text, image (OCR), voice (Whisper)
// and batch analysis. Falls back to local analysis when the backend is down.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'scam_detector.dart';

/// Result of an image OCR scan.
class ImageScanResult {
  final String extractedText;
  final double? ocrConfidence;
  final AnalysisResult analysis;

  const ImageScanResult({
    required this.extractedText,
    required this.analysis,
    this.ocrConfidence,
  });

  factory ImageScanResult.fromJson(Map<String, dynamic> json) {
    return ImageScanResult(
      extractedText: json['extracted_text'] ?? '',
      ocrConfidence: (json['ocr_confidence'] as num?)?.toDouble(),
      analysis: ApiService.parseAnalysisResult(
          json['analysis'] as Map<String, dynamic>? ?? const {}),
    );
  }
}

/// Result of a voice (Whisper) scan.
class VoiceScanResult {
  final String transcript;
  final double? audioDurationSeconds;
  final AnalysisResult analysis;

  const VoiceScanResult({
    required this.transcript,
    required this.analysis,
    this.audioDurationSeconds,
  });

  factory VoiceScanResult.fromJson(Map<String, dynamic> json) {
    return VoiceScanResult(
      transcript: json['transcript'] ?? '',
      audioDurationSeconds: (json['audio_duration_seconds'] as num?)?.toDouble(),
      analysis: ApiService.parseAnalysisResult(
          json['analysis'] as Map<String, dynamic>? ?? const {}),
    );
  }
}

/// One item in a batch scan response.
class BatchItemResult {
  final int index;
  final String textPreview;
  final AnalysisResult? result;
  final String? error;
  final bool success;

  const BatchItemResult({
    required this.index,
    required this.textPreview,
    this.result,
    this.error,
    this.success = true,
  });

  factory BatchItemResult.fromJson(Map<String, dynamic> json) {
    return BatchItemResult(
      index: json['index'] ?? 0,
      textPreview: json['text_preview'] ?? '',
      result: json['result'] == null
          ? null
          : ApiService.parseAnalysisResult(
              json['result'] as Map<String, dynamic>),
      error: json['error'] as String?,
      success: json['success'] as bool? ?? false,
    );
  }
}

/// Full batch scan response.
class BatchScanResult {
  final List<BatchItemResult> results;
  final int processed;
  final int failed;
  final int total;

  const BatchScanResult({
    required this.results,
    required this.processed,
    required this.failed,
    required this.total,
  });

  factory BatchScanResult.fromJson(Map<String, dynamic> json) {
    final items = (json['results'] as List? ?? [])
        .map((e) => BatchItemResult.fromJson(e as Map<String, dynamic>))
        .toList();
    return BatchScanResult(
      results: items,
      processed: json['processed'] ?? 0,
      failed: json['failed'] ?? 0,
      total: json['total'] ?? 0,
    );
  }
}

class ApiService {
  // Use 10.0.2.2 for Android Emulator, 127.0.0.1 for Desktop/Web
  static String get baseUrl {
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  /// Calls the FastAPI backend to analyze the text using Gemini AI.
  static Future<AnalysisResult> analyzeMessage(String text) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/analyze'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return parseAnalysisResult(data);
      } else {
        throw Exception('Failed to analyze message: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('API Error: $e');
      return AnalysisResult(
        classification: ScamClassification.suspicious,
        riskScore: 50,
        reasons: [
          DetectionReason(
            label: 'Connection Error',
            description: 'Could not connect to the analysis engine. Please try again.',
            scoreContribution: 0,
            iconCategory: IconCategory.suspicious,
          )
        ],
        summary: 'Error connecting to backend: $e',
      );
    }
  }

  /// Uploads an image and runs backend OCR (EasyOCR) + scam analysis.
  static Future<ImageScanResult> analyzeImage(String path, String filename) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/analyze-image'),
    );
    request.files.add(await http.MultipartFile.fromPath('file', path,
        filename: filename));

    final streamed = await request.send().timeout(const Duration(seconds: 90));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception('Image scan failed (HTTP ${response.statusCode}): ${response.body}');
    }
    return ImageScanResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Uploads an audio file and runs backend Whisper transcription + analysis.
  static Future<VoiceScanResult> analyzeVoice(String path, String filename) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/analyze-voice'),
    );
    request.files.add(await http.MultipartFile.fromPath('file', path,
        filename: filename));

    final streamed = await request.send().timeout(const Duration(seconds: 90));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception('Voice scan failed (HTTP ${response.statusCode}): ${response.body}');
    }
    return VoiceScanResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Sends multiple messages (max 20) for parallel backend analysis.
  static Future<BatchScanResult> analyzeBatch(List<String> items) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/analyze-batch'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'items': items}),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw Exception('Batch scan failed (HTTP ${response.statusCode}): ${response.body}');
    }
    return BatchScanResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  static AnalysisResult parseAnalysisResult(Map<String, dynamic> json) {
    return AnalysisResult(
      classification: _parseClassification(json['classification']),
      riskScore: json['riskScore'] ?? 0,
      aiPowered: json['aiPowered'] ?? true,
      category: json['category'] ?? 'unknown',
      confidence: json['confidence'] ?? 50,
      recommendedAction: json['recommended_action'] ?? 'be_cautious',
      source: json['source'] ?? 'heuristic',
      osint: json['osint'] == null
          ? null
          : OsintDetail.fromJson(json['osint'] as Map<String, dynamic>),
      reasons: (json['reasons'] as List)
          .map((r) => DetectionReason(
                label: r['label'],
                description: r['description'],
                scoreContribution: r['scoreContribution'],
                iconCategory: _parseIconCategory(r['iconCategory']),
              ))
          .toList(),
      summary: json['summary'] ?? '',
    );
  }

  static ScamClassification _parseClassification(String? value) {
    switch (value) {
      case 'scam':
        return ScamClassification.scam;
      case 'suspicious':
        return ScamClassification.suspicious;
      case 'safe':
      default:
        return ScamClassification.safe;
    }
  }

  static IconCategory _parseIconCategory(String? value) {
    switch (value) {
      case 'financial':
        return IconCategory.financial;
      case 'link':
        return IconCategory.link;
      case 'urgency':
        return IconCategory.urgency;
      case 'manipulation':
        return IconCategory.manipulation;
      case 'safe':
        return IconCategory.safe;
      case 'suspicious':
      default:
        return IconCategory.suspicious;
    }
  }
}
