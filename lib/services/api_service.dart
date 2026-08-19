// lib/services/api_service.dart
// Web-compatible API service — uses bytes/XFile instead of dart:io File.

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart'; // XFile
import 'backend_config.dart';
import 'device_identity.dart';
import 'scam_detector.dart';
import '../utils/debug_utils.dart';

class ApiService {
  static String get _baseUrl => BackendConfig.baseUrl;

  /// Calls the FastAPI backend to analyze the text using Gemini AI.
  static Future<AnalysisResult> analyzeMessage(String text) async {
    try {
      final headers = {
        'Content-Type': 'application/json',
        ...await DeviceIdentity.authHeaders(),
      };
      final response = await http.post(
        Uri.parse('$_baseUrl/analyze'),
        headers: headers,
        body: jsonEncode({'text': text}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return _parseAnalysisResult(data);
      } else {
        throw Exception('Failed to analyze message: ${response.statusCode}');
      }
    } catch (e) {
      appErrorPrint('ScamShield API error: $e', tag: 'ApiService');
      return AnalysisResult(
        classification: ScamClassification.safe,
        riskScore: 0,
        aiPowered: false,
        status: AnalysisStatus.unavailable,
        reasons: [
          DetectionReason(
            label: 'Analysis Unavailable',
            description:
                'Could not reach the analysis engine. '
                'Please check your connection and try again.',
            scoreContribution: 0,
            iconCategory: IconCategory.suspicious,
          )
        ],
        summary: 'Not analysed — the analysis service is unreachable. '
            'This is not a verdict of safety.',
      );
    }
  }

  /// Analyzes an image file picked via [XFile] — works on both web and native.
  static Future<AnalysisResult> analyzeImageXFile(XFile imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      return _uploadBytes(
        bytes: bytes,
        filename: imageFile.name,
        endpoint: '/analyze-image',
        field: 'file',
        errorLabel: 'Image OCR API error',
        failureLabel: 'Image Scan Failed',
        failureDesc: 'OCR analysis failed or backend was unreachable.',
      );
    } catch (e) {
      appErrorPrint('Image OCR API error: $e', tag: 'ApiService');
      return _unavailableResult('Image Scan Failed', 'OCR analysis failed.');
    }
  }

  /// Analyzes a voice note picked via [XFile] — works on both web and native.
  static Future<AnalysisResult> analyzeVoiceXFile(XFile audioFile) async {
    try {
      final bytes = await audioFile.readAsBytes();
      return _uploadBytes(
        bytes: bytes,
        filename: audioFile.name,
        endpoint: '/analyze-voice',
        field: 'file',
        errorLabel: 'Voice API error',
        failureLabel: 'Voice Note Scan Failed',
        failureDesc: 'Voice note analysis failed or backend was unreachable.',
      );
    } catch (e) {
      appErrorPrint('Voice API error: $e', tag: 'ApiService');
      return _unavailableResult(
          'Voice Note Scan Failed', 'Voice note analysis failed.');
    }
  }

  /// Analyzes raw file bytes (document/text file) — works on both web and native.
  static Future<AnalysisResult> analyzeFileBytes({
    required Uint8List bytes,
    required String filename,
  }) async {
    return _uploadBytes(
      bytes: bytes,
      filename: filename,
      endpoint: '/analyze-image', // backend handles docs via same OCR endpoint
      field: 'file',
      errorLabel: 'Document API error',
      failureLabel: 'Document Scan Failed',
      failureDesc: 'Document analysis failed or backend was unreachable.',
    );
  }

  // ── Internal helpers ────────────────────────────────────────────────────────

  static Future<AnalysisResult> _uploadBytes({
    required Uint8List bytes,
    required String filename,
    required String endpoint,
    required String field,
    required String errorLabel,
    required String failureLabel,
    required String failureDesc,
  }) async {
    try {
      final headers = await DeviceIdentity.authHeaders();
      final request =
          http.MultipartRequest('POST', Uri.parse('$_baseUrl$endpoint'));
      request.headers.addAll(headers);
      request.files.add(http.MultipartFile.fromBytes(
        field,
        bytes,
        filename: filename,
      ));
      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        // Image / voice endpoints return {extracted_text, analysis, ...}
        // Text endpoint returns the analysis object directly.
        final Map<String, dynamic> analysisMap =
            body.containsKey('analysis') ? body['analysis'] as Map<String, dynamic> : body;
        return _parseAnalysisResult(analysisMap);
      }
      throw Exception('${response.statusCode}: ${response.body}');
    } catch (e) {
      appErrorPrint('$errorLabel: $e', tag: 'ApiService');
      return _unavailableResult(failureLabel, failureDesc);
    }
  }

  static AnalysisResult _unavailableResult(String label, String desc) {
    return AnalysisResult(
      classification: ScamClassification.suspicious,
      riskScore: 0,
      aiPowered: false,
      status: AnalysisStatus.failed,
      reasons: [
        DetectionReason(
          label: label,
          description: desc,
          scoreContribution: 0,
          iconCategory: IconCategory.suspicious,
        )
      ],
      summary: desc,
    );
  }

  static AnalysisResult _parseAnalysisResult(Map<String, dynamic> json) {
    return AnalysisResult(
      classification: _parseClassification(json['classification']),
      riskScore: json['riskScore'] ?? 0,
      aiPowered: json['aiPowered'] ?? true,
      status: _parseStatus(json['analysisStatus']),
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

  static AnalysisStatus _parseStatus(String? value) {
    switch (value) {
      case 'partial':
        return AnalysisStatus.partial;
      case 'unavailable':
        return AnalysisStatus.unavailable;
      case 'failed':
        return AnalysisStatus.failed;
      case 'analyzed':
      default:
        return AnalysisStatus.analyzed;
    }
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
