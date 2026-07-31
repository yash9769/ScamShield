// lib/services/api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'scam_detector.dart';

class ApiService {
  // Use 10.0.2.2 for Android Emulator, 127.0.0.1 for Desktop/Web
  static const String _baseUrl = 'http://127.0.0.1:8000';

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
      print('API Error: $e');
      // If API fails, we could potentially fallback to the local keyword logic
      // But for V1, we want the AI. We'll return a basic error result for now.
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
