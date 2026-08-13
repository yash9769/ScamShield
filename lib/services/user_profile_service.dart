// lib/services/user_profile_service.dart
// Global user profile state manager for name, title, and synchronized avatar URL.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProfileService {
  static const String _nameKey = 'scamshield_user_name';
  static const String _titleKey = 'scamshield_user_title';
  static const String _avatarKey = 'scamshield_user_avatar';

  static const String defaultAvatar = 'https://i.pravatar.cc/300?u=alexchen';

  static final ValueNotifier<String> avatarNotifier = ValueNotifier<String>(defaultAvatar);
  static final ValueNotifier<String> nameNotifier = ValueNotifier<String>('Alex Chen');
  static final ValueNotifier<String> titleNotifier = ValueNotifier<String>('Intelligence Level: Advanced Protector');

  static bool _initialized = false;

  /// Preset avatars for easy user selection
  static const List<String> presetAvatars = [
    'https://i.pravatar.cc/300?u=alexchen',
    'https://i.pravatar.cc/300?u=cyber_agent',
    'https://i.pravatar.cc/300?u=guardian_shield',
    'https://i.pravatar.cc/300?u=sam_protector',
    'https://i.pravatar.cc/300?u=sarah_tech',
    'https://i.pravatar.cc/300?u=elite_defender',
  ];

  static Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_nameKey) ?? 'Alex Chen';
      final title = prefs.getString(_titleKey) ?? 'Intelligence Level: Advanced Protector';
      final avatar = prefs.getString(_avatarKey) ?? defaultAvatar;

      nameNotifier.value = name;
      titleNotifier.value = title;
      avatarNotifier.value = avatar;
      _initialized = true;
    } catch (_) {}
  }

  static Future<void> updateProfile({String? name, String? title, String? avatarUrl}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (name != null && name.isNotEmpty) {
        nameNotifier.value = name;
        await prefs.setString(_nameKey, name);
      }
      if (title != null && title.isNotEmpty) {
        titleNotifier.value = title;
        await prefs.setString(_titleKey, title);
      }
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        avatarNotifier.value = avatarUrl;
        await prefs.setString(_avatarKey, avatarUrl);
      }
    } catch (_) {}
  }
}
