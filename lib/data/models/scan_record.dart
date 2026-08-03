// lib/data/models/scan_record.dart

import '../../services/scam_detector.dart';

/// Represents a single scan result persisted in the local SQLite database.
class ScanRecord {
  final int? id;
  final String inputText;
  final String classification; // 'safe' | 'suspicious' | 'scam'
  final int riskScore;
  final String summary;
  final DateTime timestamp;
  final bool isFlagged;
  final String? source; // e.g. 'SMS', 'Clipboard', 'Manual'

  const ScanRecord({
    this.id,
    required this.inputText,
    required this.classification,
    required this.riskScore,
    required this.summary,
    required this.timestamp,
    this.isFlagged = false,
    this.source,
  });

  factory ScanRecord.fromAnalysisResult({
    required String inputText,
    required AnalysisResult result,
    String? source,
  }) {
    return ScanRecord(
      inputText: inputText,
      classification: result.classification.name,
      riskScore: result.riskScore,
      summary: result.summary,
      timestamp: DateTime.now(),
      isFlagged: result.classification == ScamClassification.scam,
      source: source ?? 'Manual',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'input_text': inputText,
      'classification': classification,
      'risk_score': riskScore,
      'summary': summary,
      'timestamp': timestamp.toIso8601String(),
      'is_flagged': isFlagged ? 1 : 0,
      'source': source,
    };
  }

  factory ScanRecord.fromMap(Map<String, dynamic> map) {
    return ScanRecord(
      id: map['id'] as int?,
      inputText: map['input_text'] as String,
      classification: map['classification'] as String,
      riskScore: map['risk_score'] as int,
      summary: map['summary'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      isFlagged: (map['is_flagged'] as int) == 1,
      source: map['source'] as String?,
    );
  }

  ScanRecord copyWith({
    int? id,
    String? inputText,
    String? classification,
    int? riskScore,
    String? summary,
    DateTime? timestamp,
    bool? isFlagged,
    String? source,
  }) {
    return ScanRecord(
      id: id ?? this.id,
      inputText: inputText ?? this.inputText,
      classification: classification ?? this.classification,
      riskScore: riskScore ?? this.riskScore,
      summary: summary ?? this.summary,
      timestamp: timestamp ?? this.timestamp,
      isFlagged: isFlagged ?? this.isFlagged,
      source: source ?? this.source,
    );
  }
}

class ScanStatistics {
  final int totalScans;
  final int scamCount;
  final int suspiciousCount;
  final int safeCount;
  final double averageRiskScore;

  const ScanStatistics({
    required this.totalScans,
    required this.scamCount,
    required this.suspiciousCount,
    required this.safeCount,
    required this.averageRiskScore,
  });

  int get threatsDetected => scamCount + suspiciousCount;
}
