// lib/data/models/user_preferences.dart

/// Stores user-configurable application preferences.
class UserPreferences {
  final bool hasConsented;
  final bool notificationsEnabled;
  final bool dailyTipEnabled;
  final int autoDeleteDays; // 0 = never, 7 / 30 / 90 = days to keep
  final bool offlineModeAcknowledged;

  /// Privacy-policy version the user last agreed to (empty = never agreed).
  final String consentVersion;

  /// ISO-8601 timestamp of when [consentVersion] was agreed to.
  final String? consentTimestamp;

  /// Optional, severable consent for sending scan content to third-party AI
  /// providers (Groq/Gemini) for enhanced analysis. Defaults to true to
  /// match pre-existing behaviour; turning it off does not disable scanning
  /// itself — it switches to the on-device heuristic engine only.
  final bool aiProcessingEnabled;

  const UserPreferences({
    this.hasConsented = false,
    this.notificationsEnabled = true,
    this.dailyTipEnabled = true,
    this.autoDeleteDays = 0,
    this.offlineModeAcknowledged = false,
    this.consentVersion = '',
    this.consentTimestamp,
    this.aiProcessingEnabled = true,
  });

  Map<String, dynamic> toMap() => {
        'has_consented': hasConsented ? 1 : 0,
        'notifications_enabled': notificationsEnabled ? 1 : 0,
        'daily_tip_enabled': dailyTipEnabled ? 1 : 0,
        'auto_delete_days': autoDeleteDays,
        'offline_mode_acknowledged': offlineModeAcknowledged ? 1 : 0,
        'consent_version': consentVersion,
        'consent_timestamp': consentTimestamp,
        'ai_processing_enabled': aiProcessingEnabled ? 1 : 0,
      };

  factory UserPreferences.fromMap(Map<String, dynamic> map) {
    return UserPreferences(
      hasConsented: (map['has_consented'] as int? ?? 0) == 1,
      notificationsEnabled: (map['notifications_enabled'] as int? ?? 1) == 1,
      dailyTipEnabled: (map['daily_tip_enabled'] as int? ?? 1) == 1,
      autoDeleteDays: map['auto_delete_days'] as int? ?? 0,
      offlineModeAcknowledged:
          (map['offline_mode_acknowledged'] as int? ?? 0) == 1,
      consentVersion: map['consent_version'] as String? ?? '',
      consentTimestamp: map['consent_timestamp'] as String?,
      aiProcessingEnabled: (map['ai_processing_enabled'] as int? ?? 1) == 1,
    );
  }

  UserPreferences copyWith({
    bool? hasConsented,
    bool? notificationsEnabled,
    bool? dailyTipEnabled,
    int? autoDeleteDays,
    bool? offlineModeAcknowledged,
    String? consentVersion,
    String? consentTimestamp,
    bool? aiProcessingEnabled,
  }) {
    return UserPreferences(
      hasConsented: hasConsented ?? this.hasConsented,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      dailyTipEnabled: dailyTipEnabled ?? this.dailyTipEnabled,
      autoDeleteDays: autoDeleteDays ?? this.autoDeleteDays,
      offlineModeAcknowledged:
          offlineModeAcknowledged ?? this.offlineModeAcknowledged,
      consentVersion: consentVersion ?? this.consentVersion,
      consentTimestamp: consentTimestamp ?? this.consentTimestamp,
      aiProcessingEnabled: aiProcessingEnabled ?? this.aiProcessingEnabled,
    );
  }
}
