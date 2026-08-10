// lib/services/api_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'scam_detector.dart';

class ApiService {
  // The Android emulator reaches the host machine via 10.0.2.2, not 127.0.0.1
  // (which resolves to the emulator itself). Hardcoding the loopback address
  // meant every text analysis silently failed on Android and fell into the
  // error path. Matches the resolution used by ScannerService/OsintService.
  static String get _baseUrl =>
      Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000';

  /// Calls the FastAPI backend to analyze the text using Gemini AI.
  static Future<AnalysisResult> analyzeMessage(String text) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/analyze'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return _parseAnalysisResult(data);
      } else {
        throw Exception('Failed to analyze message: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('ScamShield API error: $e');
      // Surface a clear, non-alarming failure state. Note the riskScore of 0
      // and the "unknown" framing: a connection failure tells us nothing about
      // the message, so scoring it 50/suspicious (as this previously did) would
      // invent a risk verdict the engine never actually produced. The raw
      // exception is logged, not shown, to avoid leaking internals to the user.
      return AnalysisResult(
        classification: ScamClassification.safe,
        riskScore: 0,
        aiPowered: false,
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
      request.files.add(await http.MultipartFile.fromPath('file', audioFile.path));
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        return _parseAnalysisResult(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('Voice API error: $e');
    }
    return const AnalysisResult(
      classification: ScamClassification.suspicious,
      riskScore: 0,
      aiPowered: false,
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
      request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        return _parseAnalysisResult(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('Image OCR API error: $e');
    }
    return const AnalysisResult(
      classification: ScamClassification.suspicious,
      riskScore: 0,
      aiPowered: false,
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
