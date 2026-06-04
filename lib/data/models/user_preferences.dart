// lib/data/models/user_preferences.dart

/// Stores user-configurable application preferences.
class UserPreferences {
  final bool hasConsented;
  final bool notificationsEnabled;
  final bool dailyTipEnabled;
  final int autoDeleteDays; // 0 = never, 7 / 30 / 90 = days to keep
  final bool offlineModeAcknowledged;

  const UserPreferences({
    this.hasConsented = false,
    this.notificationsEnabled = true,
    this.dailyTipEnabled = true,
    this.autoDeleteDays = 0,
    this.offlineModeAcknowledged = false,
  });

  Map<String, dynamic> toMap() => {
        'has_consented': hasConsented ? 1 : 0,
        'notifications_enabled': notificationsEnabled ? 1 : 0,
        'daily_tip_enabled': dailyTipEnabled ? 1 : 0,
        'auto_delete_days': autoDeleteDays,
        'offline_mode_acknowledged': offlineModeAcknowledged ? 1 : 0,
      };

  factory UserPreferences.fromMap(Map<String, dynamic> map) {
    return UserPreferences(
      hasConsented: (map['has_consented'] as int? ?? 0) == 1,
      notificationsEnabled: (map['notifications_enabled'] as int? ?? 1) == 1,
      dailyTipEnabled: (map['daily_tip_enabled'] as int? ?? 1) == 1,
      autoDeleteDays: map['auto_delete_days'] as int? ?? 0,
      offlineModeAcknowledged:
          (map['offline_mode_acknowledged'] as int? ?? 0) == 1,
    );
  }

  UserPreferences copyWith({
    bool? hasConsented,
    bool? notificationsEnabled,
    bool? dailyTipEnabled,
    int? autoDeleteDays,
    bool? offlineModeAcknowledged,
  }) {
    return UserPreferences(
      hasConsented: hasConsented ?? this.hasConsented,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      dailyTipEnabled: dailyTipEnabled ?? this.dailyTipEnabled,
      autoDeleteDays: autoDeleteDays ?? this.autoDeleteDays,
      offlineModeAcknowledged:
          offlineModeAcknowledged ?? this.offlineModeAcknowledged,
    );
  }
}
