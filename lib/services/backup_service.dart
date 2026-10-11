// lib/services/backup_service.dart
//
// Encrypted local backup and restore.
//
// ── The problem this solves ────────────────────────────────────────────────
// Cloud sync already moves scan history between devices, but it requires an
// account and a reachable server, and plenty of this app's users will have
// neither. A file the user holds themselves is the fallback: it works offline,
// it survives a factory reset, and it does not ask anyone to trust a server.
//
// ── Why the file is encrypted, not just written out ────────────────────────
// The existing "My Data" export (DataPrivacyService.exportUserData) writes
// plaintext JSON on purpose — it exists to satisfy the DPDP right of access,
// where the point is that the user can read it. A backup is a different
// artifact with a different lifetime: it gets copied to a laptop, emailed to
// oneself, left in a Downloads folder for years. Scan history is a record of
// which scams a person fell for and which bank texts they were unsure about.
// That should not be sitting in cleartext on a shared computer.
//
// ── Construction ───────────────────────────────────────────────────────────
// AES-256-GCM with a key derived from the user's passphrase by PBKDF2-HMAC-
// SHA256 over a per-backup random salt. GCM is authenticated, so a corrupted
// or tampered file fails loudly rather than restoring garbage.
//
// The header (salt, iteration count, algorithm names) has to be cleartext —
// you cannot decrypt without it — but it is passed as GCM's associated data,
// so it is authenticated too. Without that, an attacker could rewrite the
// stored iteration count down to 1 and hand the file back for a much cheaper
// offline attack, and the restore would accept the edit.
//
// ── What is deliberately not in the backup ─────────────────────────────────
// Safe Vault contents and account credentials. The vault lives in the
// platform's hardware-backed secure storage; copying it into a file protected
// only by a passphrase someone typed on a phone keyboard is a downgrade, not a
// backup. The restore screen says so, rather than letting a user assume their
// vault came along.

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../data/models/scan_record.dart';
import '../data/repositories/preferences_repository.dart';
import '../data/repositories/scan_repository.dart';
import 'settings_service.dart';
import 'user_profile_service.dart';

/// Raised for a failure the user needs to see and can act on — a wrong
/// passphrase, a file that is not a ScamShield backup, a newer format. Not
/// used for programming errors.
class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}

class BackupResult {
  final int scansRestored;
  final int scansSkipped;

  const BackupResult({required this.scansRestored, required this.scansSkipped});
}

class BackupService {
  BackupService._();

  static const String _formatTag = 'scamshield-backup';
  static const int _formatVersion = 1;

  /// OWASP's current floor for PBKDF2-HMAC-SHA256. Deliberately a named
  /// constant and written into the file: a backup restored years from now must
  /// use the iteration count it was created with, not today's.
  static const int _kdfIterations = 210000;

  static const int _saltBytes = 16;

  /// Short enough to type on a phone under stress, long enough to be worth
  /// encrypting behind. Enforced here rather than only in the UI so a caller
  /// cannot produce a backup with a two-character passphrase.
  static const int minPassphraseLength = 8;

  static final _rng = Random.secure();

  // ── Create ────────────────────────────────────────────────────────────────

  /// Produces the bytes of an encrypted backup file.
  static Future<String> create(String passphrase) async {
    if (passphrase.length < minPassphraseLength) {
      throw BackupException(
          'Use at least $minPassphraseLength characters for the passphrase.');
    }

    final payload = await _collect();
    final salt = _randomBytes(_saltBytes);

    final header = <String, dynamic>{
      'format': _formatTag,
      'version': _formatVersion,
      'kdf': 'pbkdf2-hmac-sha256',
      'iterations': _kdfIterations,
      'salt': base64Encode(salt),
      'cipher': 'aes-256-gcm',
      'createdAt': DateTime.now().toIso8601String(),
    };

    final key = await _deriveKey(passphrase, salt, _kdfIterations);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: key,
      // Binds the ciphertext to this exact header. Editing the iteration count
      // or salt after the fact makes decryption fail rather than succeed
      // cheaply.
      aad: _headerBytes(header),
    );

    return jsonEncode({
      ...header,
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    });
  }

  // ── Restore ───────────────────────────────────────────────────────────────

  /// Decrypts a backup and merges it into local storage.
  ///
  /// Merges rather than replaces: someone restoring an old backup onto a phone
  /// they have been using should not silently lose the scans they did in
  /// between. Duplicates are skipped by content, so restoring the same file
  /// twice is harmless.
  static Future<BackupResult> restore(String fileContents, String passphrase) async {
    final Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(fileContents) as Map<String, dynamic>;
    } catch (_) {
      throw const BackupException('That file is not a ScamShield backup.');
    }

    if (envelope['format'] != _formatTag) {
      throw const BackupException('That file is not a ScamShield backup.');
    }
    final version = envelope['version'];
    if (version is! int || version > _formatVersion) {
      throw const BackupException(
          'This backup was made by a newer version of ScamShield. Update the '
          'app and try again.');
    }
    if (envelope['kdf'] != 'pbkdf2-hmac-sha256' ||
        envelope['cipher'] != 'aes-256-gcm') {
      throw const BackupException('This backup uses an unsupported format.');
    }

    final iterations = envelope['iterations'];
    if (iterations is! int || iterations < 1000 || iterations > 5000000) {
      // Both directions matter: absurdly low is a tampered file, absurdly high
      // would hang the device for minutes on a file we cannot decrypt anyway.
      throw const BackupException('This backup file is damaged.');
    }

    final List<int> salt, nonce, mac, cipherText;
    try {
      salt = base64Decode(envelope['salt'] as String);
      nonce = base64Decode(envelope['nonce'] as String);
      mac = base64Decode(envelope['mac'] as String);
      cipherText = base64Decode(envelope['ciphertext'] as String);
    } catch (_) {
      throw const BackupException('This backup file is damaged.');
    }

    // Reconstructed from the envelope's own fields so it matches byte for byte
    // what create() authenticated.
    final header = <String, dynamic>{
      'format': envelope['format'],
      'version': envelope['version'],
      'kdf': envelope['kdf'],
      'iterations': envelope['iterations'],
      'salt': envelope['salt'],
      'cipher': envelope['cipher'],
      'createdAt': envelope['createdAt'],
    };

    final key = await _deriveKey(passphrase, salt, iterations);

    List<int> plain;
    try {
      plain = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
        aad: _headerBytes(header),
      );
    } catch (e) {
      // GCM cannot distinguish a wrong key from a modified file, so neither
      // can this message. Leading with the likely cause is more useful than
      // being vague about both.
      debugPrint('BackupService.restore: authentication failed ($e)');
      throw const BackupException(
          'Wrong passphrase, or the file has been changed since it was made.');
    }

    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    } catch (_) {
      throw const BackupException('This backup file is damaged.');
    }

    return _apply(payload);
  }

  /// Reads a backup's header without needing the passphrase, so the restore
  /// screen can show when it was made before asking the user to type anything.
  static DateTime? peekCreatedAt(String fileContents) {
    try {
      final envelope = jsonDecode(fileContents) as Map<String, dynamic>;
      if (envelope['format'] != _formatTag) return null;
      return DateTime.tryParse(envelope['createdAt'] as String? ?? '');
    } catch (_) {
      return null;
    }
  }

  // ── Payload ───────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _collect() async {
    final scans = await ScanRepository().loadHistory();
    final prefs = await PreferencesRepository().load();

    return {
      'scans': scans
          .map((s) => {
                'inputText': s.inputText,
                'classification': s.classification,
                'riskScore': s.riskScore,
                'summary': s.summary,
                'timestamp': s.timestamp.toIso8601String(),
                'isFlagged': s.isFlagged,
                'source': s.source,
              })
          .toList(),
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
      // Safe Vault contents and credentials are excluded on purpose — see the
      // header comment on this file.
    };
  }

  static Future<BackupResult> _apply(Map<String, dynamic> payload) async {
    final repo = ScanRepository();
    final existing = await repo.loadHistory();

    // Content identity, not database id: the ids in a backup belong to the
    // device it came from and mean nothing here.
    final seen = existing
        .map((s) => '${s.inputText}|${s.timestamp.toIso8601String()}|${s.source}')
        .toSet();

    var restored = 0;
    var skipped = 0;
    for (final raw in (payload['scans'] as List<dynamic>? ?? [])) {
      try {
        final map = raw as Map<String, dynamic>;
        final timestamp = DateTime.parse(map['timestamp'] as String);
        final key = '${map['inputText']}|${timestamp.toIso8601String()}|${map['source']}';
        if (seen.contains(key)) {
          skipped++;
          continue;
        }
        await repo.saveScan(ScanRecord(
          inputText: map['inputText'] as String,
          classification: map['classification'] as String,
          riskScore: map['riskScore'] as int,
          summary: map['summary'] as String? ?? '',
          timestamp: timestamp,
          isFlagged: map['isFlagged'] == true,
          source: map['source'] as String?,
        ));
        seen.add(key);
        restored++;
      } catch (e) {
        // One malformed record must not abandon the rest of the restore.
        debugPrint('BackupService: skipping unreadable scan record ($e)');
        skipped++;
      }
    }

    try {
      final profile = payload['profile'] as Map<String, dynamic>?;
      if (profile != null) {
        await UserProfileService.updateProfile(
          name: profile['name'] as String?,
          title: profile['title'] as String?,
          avatarUrl: profile['avatarUrl'] as String?,
        );
      }

      final settings = payload['settings'] as Map<String, dynamic>?;
      if (settings != null) {
        if (settings['threatAlerts'] is bool) {
          await SettingsService.setThreatAlerts(settings['threatAlerts'] as bool);
        }
        if (settings['autoScanClipboard'] is bool) {
          await SettingsService.setAutoScanClipboard(
              settings['autoScanClipboard'] as bool);
        }
      }
    } catch (e) {
      // Settings are a convenience; the scan history is the part worth
      // failing over, and it has already been written by this point.
      debugPrint('BackupService: could not restore settings ($e)');
    }

    return BackupResult(scansRestored: restored, scansSkipped: skipped);
  }

  // ── Crypto helpers ────────────────────────────────────────────────────────

  static Future<SecretKey> _deriveKey(
      String passphrase, List<int> salt, int iterations) async {
    final pbkdf2 = Pbkdf2.hmacSha256(iterations: iterations, bits: 256);
    return pbkdf2.deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  /// Canonical bytes of the header for use as GCM associated data. Key order
  /// is fixed by construction in both create() and restore(), so the two sides
  /// always produce the same bytes — a map iterated in a different order would
  /// make every restore fail.
  static List<int> _headerBytes(Map<String, dynamic> header) =>
      utf8.encode(jsonEncode(header));

  static List<int> _randomBytes(int count) =>
      List<int>.generate(count, (_) => _rng.nextInt(256));
}
