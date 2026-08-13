// lib/services/api_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
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
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return _parseAnalysisResult(data);
      } else {
        throw Exception('Failed to analyze message: ${response.statusCode}');
      }
    } catch (e) {
      appErrorPrint('ScamShield API error: $e', tag: 'ApiService');
      // A connection failure tells us nothing about the message. We MUST NOT
      // return a green "safe" verdict here: the classification field is
      // neutral and the explicit status is [AnalysisStatus.unavailable], which
      // the UI renders as "NOT ANALYZED", never as safety.
      return AnalysisResult(
        classification: ScamClassification.safe,
        riskScore: 0,
        aiPowered: false,
        status: AnalysisStatus.unavailable,
        reasons: [
          DetectionReason(
            label: 'Analysis Unavailable',
            description:
                'Could not reach the analysis engine, so this message has NOT been checked. '
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

  /// Calls the FastAPI backend to analyze a voice note file.
  static Future<AnalysisResult> analyzeVoice(File audioFile) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/analyze-voice'));
      request.headers.addAll(await DeviceIdentity.authHeaders());
      request.files.add(await http.MultipartFile.fromPath('file', audioFile.path));
      final streamedResponse = await request.send().timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamedResponse).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return _parseAnalysisResult(jsonDecode(response.body));
      }
    } catch (e) {
      appErrorPrint('Voice API error: $e', tag: 'ApiService');
    }
    return const AnalysisResult(
      classification: ScamClassification.suspicious,
      riskScore: 0,
      aiPowered: false,
      status: AnalysisStatus.failed,
      reasons: [
        DetectionReason(
          label: 'Voice Note Scan Failed',
          description: 'Voice note analysis failed or backend was unreachable.',
          scoreContribution: 0,
          iconCategory: IconCategory.suspicious,
        )
      ],
      summary: 'Voice note could not be analyzed because the service was unreachable or returned an error.',
    );
  }

  /// Calls the FastAPI backend to analyze a screenshot image file via OCR.
  static Future<AnalysisResult> analyzeImage(File imageFile) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/analyze-image'));
      request.headers.addAll(await DeviceIdentity.authHeaders());
      request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
      final streamedResponse = await request.send().timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamedResponse).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return _parseAnalysisResult(jsonDecode(response.body));
      }
    } catch (e) {
      appErrorPrint('Image OCR API error: $e', tag: 'ApiService');
    }
    return const AnalysisResult(
      classification: ScamClassification.suspicious,
      riskScore: 0,
      aiPowered: false,
      status: AnalysisStatus.failed,
      reasons: [
        DetectionReason(
          label: 'Image Scan Failed',
          description: 'OCR analysis failed or backend was unreachable.',
          scoreContribution: 0,
          iconCategory: IconCategory.suspicious,
        )
      ],
      summary: 'OCR image analysis failed because the service was unreachable or returned an error.',
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
