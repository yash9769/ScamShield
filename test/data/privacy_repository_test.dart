// test/data/privacy_repository_test.dart
//
// DPDP regression tests for the SQLite-backed privacy controls: scan
// deletion (single/all), retention cleanup, and the consent/AI-processing
// preference record. Runs against a real SQLite database via
// sqflite_common_ffi (no device/emulator required).

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:scamshield/data/database/database_helper.dart';
import 'package:scamshield/data/models/scan_record.dart';
import 'package:scamshield/data/repositories/scan_repository.dart';
import 'package:scamshield/data/repositories/preferences_repository.dart';
import 'package:scamshield/services/consent_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper dbHelper;
  late ScanRepository scanRepo;
  late PreferencesRepository prefsRepo;

  setUp(() async {
    // DatabaseHelper is a singleton backed by a file on disk (even under the
    // ffi test backend), so each test must close AND delete it — otherwise
    // state leaks between tests that assume an empty history at start.
    dbHelper = DatabaseHelper.instance;
    await dbHelper.close();
    final dbPath = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dbPath, 'scamshield.db'));
    scanRepo = ScanRepository(dbHelper: dbHelper);
    prefsRepo = PreferencesRepository(dbHelper: dbHelper);
  });

  tearDown(() async {
    await dbHelper.close();
  });

  ScanRecord makeRecord({required String text, DateTime? timestamp}) {
    return ScanRecord(
      inputText: text,
      classification: 'scam',
      riskScore: 90,
      summary: 'test summary',
      timestamp: timestamp ?? DateTime.now(),
      isFlagged: true,
      source: 'Manual',
    );
  }

  group('ScanRepository — deletion (right to erasure)', () {
    test('deleteById removes only the targeted scan', () async {
      final id1 = await scanRepo.saveScan(makeRecord(text: 'keep me'));
      final id2 = await scanRepo.saveScan(makeRecord(text: 'delete me'));

      await scanRepo.deleteById(id2);

      final remaining = await scanRepo.loadHistory();
      expect(remaining.map((r) => r.id), contains(id1));
      expect(remaining.map((r) => r.id), isNot(contains(id2)));
    });

    test('clearAll removes every scan record', () async {
      await scanRepo.saveScan(makeRecord(text: 'a'));
      await scanRepo.saveScan(makeRecord(text: 'b'));
      await scanRepo.saveScan(makeRecord(text: 'c'));

      await scanRepo.clearAll();

      expect(await scanRepo.loadHistory(), isEmpty);
    });

    test('deleting a non-existent id is a no-op, not an error', () async {
      await scanRepo.saveScan(makeRecord(text: 'a'));
      await scanRepo.deleteById(999999);
      expect(await scanRepo.loadHistory(), hasLength(1));
    });

    test('a deletion made via one ScanRepository instance is visible from another', () async {
      // Regression test: every screen constructs its own `ScanRepository()`
      // (see lib/screens/history_screen.dart, privacy_settings_screen.dart,
      // data_privacy_service.dart, etc). Each instance used to get its own
      // private LocalCache, so "Delete My Data" (a different instance than
      // the History screen's) would clear the database but the History
      // screen would keep showing its stale cached list until some other
      // write happened to invalidate it — the user's erasure request would
      // appear to silently fail. ScanRepository now shares one cache across
      // instances by default specifically to prevent this.
      final screenA = ScanRepository(dbHelper: dbHelper);
      final screenB = ScanRepository(dbHelper: dbHelper);

      await screenA.saveScan(makeRecord(text: 'visible everywhere'));
      // screenB "opens the History screen" and loads (and caches) the list.
      expect(await screenB.loadHistory(), hasLength(1));

      // A different screen instance (e.g. Privacy & Data) erases everything.
      await screenA.clearHistory();

      // screenB must not keep serving the stale cached list.
      expect(await screenB.loadHistory(), isEmpty);
    });
  });

  group('ScanRepository — retention cleanup', () {
    test('deleteOlderThan removes only records past the cutoff', () async {
      final old = makeRecord(
        text: 'old scan',
        timestamp: DateTime.now().subtract(const Duration(days: 100)),
      );
      final recent = makeRecord(
        text: 'recent scan',
        timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      );
      await scanRepo.saveScan(old);
      await scanRepo.saveScan(recent);

      final removed = await scanRepo.deleteOlderThan(30);

      expect(removed, 1);
      final remaining = await scanRepo.loadHistory();
      expect(remaining, hasLength(1));
      expect(remaining.first.inputText, 'recent scan');
    });

    test('deleteOlderThan(0 effectively unused) leaves nothing when never called', () async {
      await scanRepo.saveScan(makeRecord(text: 'a'));
      // Retention is opt-in (autoDeleteDays defaults to 0 / "never") — the
      // app must not silently purge history unless the user configured it.
      final prefs = await prefsRepo.load();
      expect(prefs.autoDeleteDays, 0);
      expect(await scanRepo.loadHistory(), hasLength(1));
    });
  });

  group('PreferencesRepository — consent record', () {
    test('defaults to no consent and AI processing enabled', () async {
      final prefs = await prefsRepo.load();
      expect(prefs.hasConsented, isFalse);
      expect(prefs.consentVersion, isEmpty);
      expect(prefs.consentTimestamp, isNull);
      expect(prefs.aiProcessingEnabled, isTrue);
    });

    test('grantConsent records version and a timestamp', () async {
      await prefsRepo.grantConsent('1.0.0');
      final prefs = await prefsRepo.load();
      expect(prefs.hasConsented, isTrue);
      expect(prefs.consentVersion, '1.0.0');
      expect(prefs.consentTimestamp, isNotNull);
      expect(DateTime.tryParse(prefs.consentTimestamp!), isNotNull);
    });

    test('setAiProcessingEnabled is independent of essential consent', () async {
      await prefsRepo.grantConsent('1.0.0');
      await prefsRepo.setAiProcessingEnabled(false);

      final prefs = await prefsRepo.load();
      expect(prefs.hasConsented, isTrue, reason: 'withdrawing AI consent must not revoke essential consent');
      expect(prefs.aiProcessingEnabled, isFalse);
    });

    test('resetToDefaults clears the consent record (used by account deletion)', () async {
      await prefsRepo.grantConsent('1.0.0');
      await prefsRepo.setAutoDelete(90);

      await prefsRepo.resetToDefaults();

      final prefs = await prefsRepo.load();
      expect(prefs.hasConsented, isFalse);
      expect(prefs.consentVersion, isEmpty);
      expect(prefs.autoDeleteDays, 0);
    });
  });

  group('ConsentService — consent-state handling', () {
    test('hasGivenCurrentConsent is false before any consent is granted', () async {
      final service = ConsentService(repository: prefsRepo);
      expect(await service.hasGivenCurrentConsent(), isFalse);
    });

    test('hasGivenCurrentConsent is true after granting the current policy version', () async {
      final service = ConsentService(repository: prefsRepo);
      await service.grantEssentialConsent();
      expect(await service.hasGivenCurrentConsent(), isTrue);
    });

    test('consent for an old policy version does not satisfy the current one', () async {
      // Simulates a user who agreed before a policy bump.
      await prefsRepo.grantConsent('0.0.1-old');
      final service = ConsentService(repository: prefsRepo);
      expect(await service.hasGivenCurrentConsent(), isFalse);
    });

    test('AI-processing consent toggles independently and is reflected immediately', () async {
      final service = ConsentService(repository: prefsRepo);
      expect(await service.isAiProcessingEnabled(), isTrue);

      await service.setAiProcessingEnabled(false);
      expect(await service.isAiProcessingEnabled(), isFalse);
      expect(ConsentService.aiProcessingEnabled.value, isFalse);

      await service.setAiProcessingEnabled(true);
      expect(await service.isAiProcessingEnabled(), isTrue);
    });

    test('consentRecord reports the current and agreed policy versions', () async {
      final service = ConsentService(repository: prefsRepo);
      await service.grantEssentialConsent();
      final record = await service.consentRecord();
      expect(record['privacyPolicyVersionAgreed'], ConsentService.currentPolicyVersion);
      expect(record['currentPrivacyPolicyVersion'], ConsentService.currentPolicyVersion);
      expect(record['agreedAt'], isNotNull);
      expect(record['aiProcessingConsent'], isTrue);
    });
  });
}
