// lib/services/permission_service.dart
// Centralized service for requesting permissions once and persisting consent.

import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionService {
  static const String _permissionsGrantedKey = 'scamshield_all_permissions_granted';

  /// Check if permissions have already been requested & granted once.
  static Future<bool> hasGrantedPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_permissionsGrantedKey) ?? false;
  }

  /// Request all essential app permissions once.
  static Future<bool> requestAllPermissionsOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_permissionsGrantedKey) == true) {
      return true;
    }

    try {
      if (Platform.isAndroid) {
        final statuses = await [
          Permission.storage,
          Permission.photos,
          Permission.notification,
        ].request();

        final isGranted = statuses.values.any((s) => s.isGranted || s.isLimited);
        if (isGranted) {
          await prefs.setBool(_permissionsGrantedKey, true);
        }
        return isGranted;
      } else if (Platform.isIOS) {
        final statuses = await [
          Permission.photos,
          Permission.notification,
        ].request();

        final isGranted = statuses.values.any((s) => s.isGranted || s.isLimited);
        if (isGranted) {
          await prefs.setBool(_permissionsGrantedKey, true);
        }
        return isGranted;
      }
    } catch (_) {}

    await prefs.setBool(_permissionsGrantedKey, true);
    return true;
  }
}
