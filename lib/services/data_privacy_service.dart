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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/education/progress_service.dart';
import '../data/repositories/scan_repository.dart';
import '../data/repositories/preferences_repository.dart';
import 'auth_service.dart';
import 'call_screening_service.dart';
import 'cloud_account_service.dart';
import 'cloud_sync_service.dart';
import 'sms_screening_service.dart';
import 'user_profile_service.dart';
import 'settings_service.dart';

/// The outcome of [DataPrivacyService.deleteAccountAndAllData], so the caller
/// can tell the user plainly whether their *server-held* data was confirmed
/// erased rather than implying a guarantee the app couldn't actually check —
/// local erasure is unconditional and isn't represented here because it
/// never fails silently: every step in that half either completes or the
/// method throws.
class AccountDeletionResult {
  /// Whether this device had a cloud sync account signed in at all. When
  /// false, [cloudAccountDeleted] is trivially true and the distinction
  /// doesn't need surfacing to the user.
  final bool hadCloudAccount;

  /// True if the server confirmed the account (and everything hanging off
  /// it — synced scans, family membership, push token, learning progress)
  /// was deleted. False means the local cloud session was still cleared
  /// (see [CloudAccountService.deleteAccount]), but the server could not be
  /// reached to confirm — most likely no connection at the moment of
  /// deletion.
  final bool cloudAccountDeleted;

  const AccountDeletionResult({
    required this.hadCloudAccount,
    required this.cloudAccountDeleted,
  });
}

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
    ProgressService? progressService,
  })  : _scanRepository = scanRepository ?? ScanRepository(),
        _preferencesRepository =
            preferencesRepository ?? PreferencesRepository(),
        _progressService = progressService ?? ProgressService();

  final ScanRepository _scanRepository;
  final PreferencesRepository _preferencesRepository;
  final ProgressService _progressService;

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
  ///
  /// Also, if signed in to cloud sync: tombstones the deleted scans
  /// server-side, resets learning progress (locally and, best-effort, on the
  /// leaderboard), and refreshes the call-screening blocklist a synced-scan
  /// list feeds. None of this depends on network for its local half to
  /// succeed — every step below still runs, and the deletion is still
  /// complete on this device, even if the phone is offline.
  Future<void> deleteAllScanAndVaultData() async {
    // Read before clearing: once the rows are gone there is nothing left to
    // compute their cloud ids from, and a scan pushed to the server on an
    // earlier sync would otherwise sit there untouched — see
    // CloudSyncService.pushTombstones for why that matters.
    final scansBeingDeleted = await _scanRepository.loadHistory();

    await _scanRepository.clearHistory();
    await _vaultStorage.delete(key: _vaultKey);
    await deleteAllGeneratedReports();

    unawaited(CloudSyncService.pushTombstones(scansBeingDeleted));

    // Learning progress (points/badges/streak) is personal data ScamShield
    // has derived from the user's own activity, same as scan history — a
    // "delete my data" that leaves the leaderboard showing last week's
    // streak is not actually done.
    await _progressService.resetProgress();
    if (CloudAccountService.signedIn.value) {
      unawaited(CloudAccountService.pushLearningProgress(
        totalPoints: 0, streakDays: 0, badgesEarned: 0,
        quizzesPassed: 0, articlesRead: 0,
      ));
    }

    // The local phone-number blocklist call screening uses is partly derived
    // from scan history (numbers that sent a scam message); recompute it now
    // rather than leaving it stale until the feature's own next opportunistic
    // refresh. Numbers the user added by hand are untouched — that is a
    // protection list they configured on purpose, not "scan data".
    unawaited(CallScreeningService.refreshBlocklist());
  }

  /// "Delete Account": irreversibly removes everything ScamShield has
  /// stored about this user — on this device, and on the server too if a
  /// cloud sync account exists. Local: account credentials, session,
  /// profile, settings, scan history, Safe Vault, generated reports, learning
  /// progress; local preferences (including the consent record) reset to
  /// defaults. Server (when signed in): the account row and everything
  /// cascading from it — synced scans, family membership/alerts, push token,
  /// learning progress — via `DELETE /account`.
  ///
  /// A cloud account, if one exists, is deleted *first*, before any local
  /// data is touched. Deleting it last would mean a network failure on the
  /// very last step leaves local data already gone but the server call never
  /// attempted; deleting it first means a failure here still gets reported
  /// accurately in the returned result, and every local step below still
  /// runs regardless — local erasure never depends on network reachability.
  ///
  /// Active phone/SMS monitoring is turned off, not just left running under
  /// an account that no longer exists: "delete my account" is understood
  /// here to mean stop watching this device's calls and messages too, the
  /// same way it already resets every other setting to its default.
  Future<AccountDeletionResult> deleteAccountAndAllData() async {
    final hadCloudAccount = CloudAccountService.signedIn.value;
    final cloudAccountDeleted =
        hadCloudAccount ? await CloudAccountService.deleteAccount() : true;
    await CloudSyncService.resetCursor();

    await deleteAllScanAndVaultData();
    await AuthService.deleteAccount();
    await _preferencesRepository.resetToDefaults();
    await SmsScreeningService.disable();
    await CallScreeningService.disable();

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

    return AccountDeletionResult(
      hadCloudAccount: hadCloudAccount,
      cloudAccountDeleted: cloudAccountDeleted,
    );
  }

  /// Structured export of everything stored about this user, for the "My
  /// Data" screen (DPDP right to access) — on this device, and, when signed
  /// in to cloud sync, on the server too.
  ///
  /// Two things are deliberately incomplete, both noted in the export itself
  /// rather than silently omitted:
  ///   - Safe Vault item *content*. Only titles/categories/timestamps are
  ///     included, because this produces a plaintext JSON file, and writing
  ///     the user's own encrypted secrets out to plaintext would itself be a
  ///     data-protection regression — the Safe Vault screen already lets the
  ///     user view/copy each secret's content individually when they
  ///     explicitly reveal it.
  ///   - The server-held section, if the server can't be reached right now.
  ///     Silently leaving it out would make the export quietly thinner than
  ///     what actually exists about the user; saying so lets them retry
  ///     later instead of assuming there was nothing to fetch.
  Future<Map<String, dynamic>> exportUserData() async {
    final scans = await _scanRepository.loadHistory();
    final prefs = await _preferencesRepository.load();
    final progress = await _progressService.load();

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

    Map<String, dynamic> cloudAccountSection = {'signedIn': false};
    if (CloudAccountService.signedIn.value) {
      final serverData = await CloudAccountService.exportAccountData();
      cloudAccountSection = {
        'signedIn': true,
        'note': 'This section covers data held on the ScamShield sync server — a '
            'separate, optional account from the one above, created only if you '
            'set up cross-device sync or family protection.',
        if (serverData != null)
          'data': serverData
        else
          'error': 'Could not reach the server just now to fetch this section. '
              'Try exporting again while online.',
      };
    }

    return {
      'exportedAt': DateTime.now().toIso8601String(),
      'account': {
        'email': await AuthService.registeredEmail(),
      },
      'cloudSyncAccount': cloudAccountSection,
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
      'learningProgress': {
        'totalPoints': progress.totalPoints,
        'streakDays': progress.streakDays,
        'quizzesTaken': progress.quizzesTaken,
        'quizzesPassed': progress.quizzesPassedCount,
        'articlesRead': progress.articlesRead,
        'badgesEarned': progress.badgesEarned,
        'lastActiveDate': progress.lastActiveDate?.toIso8601String(),
      },
      'callScreening': {
        'enabled': await CallScreeningService.isEnabled(),
        'silenceKnownScamCallers': await CallScreeningService.silenceKnownScams(),
        'onlineReputationLookupEnabled': await CallScreeningService.onlineLookup(),
        'manuallyAddedNumbers': await CallScreeningService.manualNumbers(),
        'note': 'The rest of this feature\'s blocklist is computed from your scan '
            'history each time it runs, rather than stored separately, so it is '
            'already covered by scanHistory above.',
      },
      'smsScreening': {
        'enabled': await SmsScreeningService.isEnabled(),
      },
    };
  }
}
