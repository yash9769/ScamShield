// lib/services/consent_service.dart
//
// DPDP consent-management service.
//
// Two separable kinds of consent are tracked:
//  - "Essential" consent: agreement to the Privacy Policy describing the
//    on-device processing ScamShield performs to function at all (storing
//    scan history locally, hashing your password, etc). Captured once via a
//    clear affirmative action (ConsentScreen) before the app can be used,
//    never pre-selected. Re-requested automatically whenever
//    [currentPolicyVersion] changes.
//  - "AI processing" consent: optional, and does not gate any unrelated
//    functionality — turning it off only switches scan analysis from the
//    Groq/Gemini-backed backend to the on-device heuristic engine. Defaults
//    to enabled (matching the app's pre-existing behaviour) and can be
//    withdrawn at any time from Settings > Privacy & Data.
//
// This replaces the previously dead `PreferencesRepository`/`has_consented`
// scaffold with a live flow actually wired into the app.

import 'package:flutter/foundation.dart';

import '../data/repositories/preferences_repository.dart';

class ConsentService {
  ConsentService({PreferencesRepository? repository})
      : _repository = repository ?? PreferencesRepository();

  final PreferencesRepository _repository;

  /// Bump this whenever the Privacy Policy materially changes; users will be
  /// re-prompted for essential consent on next launch.
  static const String currentPolicyVersion = '1.0.0';

  /// Reactive flag other widgets can listen to without re-querying SQLite.
  static final ValueNotifier<bool> aiProcessingEnabled =
      ValueNotifier<bool>(true);

  bool _cachedHasCurrentConsent = false;

  /// True once the user has agreed to [currentPolicyVersion] specifically —
  /// agreeing to an older version does not count after a policy change.
  Future<bool> hasGivenCurrentConsent() async {
    final prefs = await _repository.load();
    _cachedHasCurrentConsent =
        prefs.hasConsented && prefs.consentVersion == currentPolicyVersion;
    aiProcessingEnabled.value = prefs.aiProcessingEnabled;
    return _cachedHasCurrentConsent;
  }

  /// Records affirmative agreement to the current Privacy Policy version,
  /// with a timestamp, as required for a valid consent record.
  Future<void> grantEssentialConsent() async {
    await _repository.grantConsent(currentPolicyVersion);
    _cachedHasCurrentConsent = true;
  }

  Future<bool> isAiProcessingEnabled() async {
    final prefs = await _repository.load();
    aiProcessingEnabled.value = prefs.aiProcessingEnabled;
    return prefs.aiProcessingEnabled;
  }

  /// Grants or withdraws the optional AI-processing consent. Withdrawing it
  /// does not affect any other feature — scanning still works locally.
  Future<void> setAiProcessingEnabled(bool value) async {
    await _repository.setAiProcessingEnabled(value);
    aiProcessingEnabled.value = value;
  }

  /// Full consent record, for display on the "My Data" screen and for data
  /// export.
  Future<Map<String, dynamic>> consentRecord() async {
    final prefs = await _repository.load();
    return {
      'privacyPolicyVersionAgreed': prefs.consentVersion.isEmpty
          ? null
          : prefs.consentVersion,
      'currentPrivacyPolicyVersion': currentPolicyVersion,
      'agreedAt': prefs.consentTimestamp,
      'aiProcessingConsent': prefs.aiProcessingEnabled,
    };
  }
}
