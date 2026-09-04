// lib/services/data_privacy_service.dart
//
// Central place for DPDP erasure/export/retention operations that touch
// more than one storage location. Individual repositories/services already
// own deletion of their own data (ScanRepository.clearAll(),
// AuthService.deleteAccount(), etc) — this service composes them into the
// two user-facing actions Settings > Privacy & Data offers ("Delete My
// Data" and "Delete Account"), plus a JSON export and best-effort cleanup
// of generated report files that previously had no deletion path at all
// (see DPDP_AUDIT.md §13).

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repositories/scan_repository.dart';
import '../data/repositories/preferences_repository.dart';
import 'auth_service.dart';
import 'user_profile_service.dart';
import 'settings_service.dart';

/// Matches the generated-report filenames used by ReportGeneratorService
/// (ScamShield_Report_*.pdf, ScamShield_ServerReport_*.pdf,
/// ScamShield_AuditReport_*.pdf), in both the app-documents and temp dirs.
final RegExp _reportFilePattern = RegExp(r'^ScamShield_.*\.pdf$');

const _vaultStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
const _vaultKey = 'scamshield_vault_notes';

class DataPrivacyService {
  DataPrivacyService({
    ScanRepository? scanRepository,
    PreferencesRepository? preferencesRepository,
  })  : _scanRepository = scanRepository ?? ScanRepository(),
        _preferencesRepository =
            preferencesRepository ?? PreferencesRepository();

  final ScanRepository _scanRepository;
  final PreferencesRepository _preferencesRepository;

  /// Deletes every generated PDF report this app has ever written, in both
  /// the persistent app-documents directory and the OS temp directory.
  /// Best-effort: failures for individual files are swallowed so one locked
  /// file cannot block the rest of an erasure request.
  Future<int> deleteAllGeneratedReports() async {
    var deleted = 0;
    for (final dir in await _reportDirectories()) {
      deleted += await _deleteMatchingFiles(dir, _reportFilePattern);
    }
    return deleted;
  }

  /// Best-effort startup cleanup: removes report files from the *temporary*
  /// directory (only) older than [maxAge]. The temp directory is meant for
  /// transient output; the app-documents copy is treated as a
  /// user-retained saved report and is only removed by an explicit erasure
  /// action ([deleteAllGeneratedReports]) so a report the user meant to keep
  /// is never silently deleted by a background job.
  Future<int> cleanupStaleTempReports(
      {Duration maxAge = const Duration(days: 7)}) async {
    try {
      final dir = await getTemporaryDirectory();
      if (!await dir.exists()) return 0;
      var deleted = 0;
      final cutoff = DateTime.now().subtract(maxAge);
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments.last
            : '';
        if (!_reportFilePattern.hasMatch(name)) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
            deleted++;
          }
        } catch (_) {}
      }
      return deleted;
    } catch (_) {
      return 0;
    }
  }

  Future<List<Directory>> _reportDirectories() async {
    final dirs = <Directory>[];
    try {
      dirs.add(await getApplicationDocumentsDirectory());
    } catch (_) {}
    try {
      dirs.add(await getTemporaryDirectory());
    } catch (_) {}
    return dirs;
  }

  Future<int> _deleteMatchingFiles(Directory dir, RegExp pattern) async {
    if (!await dir.exists()) return 0;
    var deleted = 0;
    try {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments.last
            : '';
        if (!pattern.hasMatch(name)) continue;
        try {
          await entity.delete();
          deleted++;
        } catch (_) {}
      }
    } catch (_) {}
    return deleted;
  }

  /// "Delete My Data": clears scan history, all Safe Vault items, and every
  /// generated report — but keeps the account itself (email/password) so
  /// the user stays signed in. Profile display fields (name/title/avatar)
  /// are intentionally left untouched here; use [deleteAccountAndAllData]
  /// to remove those too.
  Future<void> deleteAllScanAndVaultData() async {
    await _scanRepository.clearHistory();
    await _vaultStorage.delete(key: _vaultKey);
    await deleteAllGeneratedReports();
  }

  /// "Delete Account": irreversibly removes everything ScamShield has
  /// stored about this user on this device — account credentials, session,
  /// profile, settings, scan history, Safe Vault, generated reports, and
  /// resets local preferences (including the consent record) to defaults.
  /// There is no server-side account to delete (see DPDP_AUDIT.md §0) so
  /// this is a complete erasure.
  Future<void> deleteAccountAndAllData() async {
    await deleteAllScanAndVaultData();
    await AuthService.deleteAccount();
    await _preferencesRepository.resetToDefaults();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('scamshield_user_name');
      await prefs.remove('scamshield_user_title');
      await prefs.remove('scamshield_user_avatar');
      await prefs.remove('scamshield_threat_alerts');
      await prefs.remove('scamshield_auto_scan_clipboard');
      await prefs.remove('scamshield_all_permissions_granted');
    } catch (_) {}

    UserProfileService.nameNotifier.value = 'Alex Chen';
    UserProfileService.titleNotifier.value =
        'Intelligence Level: Advanced Protector';
    UserProfileService.avatarNotifier.value =
        UserProfileService.defaultAvatar;
    SettingsService.threatAlerts.value = true;
    SettingsService.autoScanClipboard.value = false;
  }

  /// Structured export of everything stored about this user on this device,
  /// for the "My Data" screen (DPDP right to access). Safe Vault item
  /// *content* is deliberately excluded — only titles/categories/timestamps
  /// are included — because this produces a plaintext JSON file, and
  /// writing the user's own encrypted secrets out to plaintext would itself
  /// be a data-protection regression; the Safe Vault screen already lets
  /// the user view/copy each secret's content individually when they
  /// explicitly reveal it.
  Future<Map<String, dynamic>> exportUserData() async {
    final scans = await _scanRepository.loadHistory();
    final prefs = await _preferencesRepository.load();

    List<Map<String, dynamic>> vaultSummary = [];
    try {
      final raw = await _vaultStorage.read(key: _vaultKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        vaultSummary = decoded
            .map((e) => {
                  'title': e['title'],
                  'category': e['category'],
                  'createdAt': e['createdAt'],
                })
            .toList()
            .cast<Map<String, dynamic>>();
      }
    } catch (_) {}

    return {
      'exportedAt': DateTime.now().toIso8601String(),
      'account': {
        'email': await AuthService.registeredEmail(),
      },
      'profile': {
        'name': UserProfileService.nameNotifier.value,
        'title': UserProfileService.titleNotifier.value,
        'avatarUrl': UserProfileService.avatarNotifier.value,
      },
      'settings': {
        'threatAlerts': SettingsService.threatAlerts.value,
        'autoScanClipboard': SettingsService.autoScanClipboard.value,
        'autoDeleteDays': prefs.autoDeleteDays,
      },
      'consent': {
        'privacyPolicyVersionAgreed':
            prefs.consentVersion.isEmpty ? null : prefs.consentVersion,
        'agreedAt': prefs.consentTimestamp,
        'aiProcessingConsent': prefs.aiProcessingEnabled,
      },
      'scanHistory': scans
          .map((s) => {
                'id': s.id,
                'inputText': s.inputText,
                'classification': s.classification,
                'riskScore': s.riskScore,
                'summary': s.summary,
                'timestamp': s.timestamp.toIso8601String(),
                'source': s.source,
              })
          .toList(),
      'safeVaultItems (titles/categories only — see note)': vaultSummary,
    };
  }
}
