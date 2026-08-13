import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/services/apk_analyzer_service.dart';
import 'package:scamshield/services/scam_detector.dart';

import 'helpers/build_test_apks.dart';

void main() {
  group('APK Analyzer Engine Tests', () {
    setUpAll(ensureFixtures);

    const apkDir = 'ScamShield_Test_APKs';

    test('1_benign_debug.apk should be classified as safe with score 0-5', () async {
      final apkPath = '$apkDir/1_benign_debug.apk';
      final apkResult = await ApkAnalyzerService.analyzeApk(apkPath);
      
      final analysis = ScamDetector.analyzeApk(apkResult, []);
      
      expect(analysis.riskScore, lessThanOrEqualTo(5));
      expect(analysis.classification, ScamClassification.safe);
      expect(apkResult.permissions, isNot(contains('READ_SMS')));
      expect(apkResult.secrets, isEmpty);
    });

    test('2_permissions_debug.apk should detect dangerous permissions', () async {
      final apkPath = '$apkDir/2_permissions_debug.apk';
      final apkResult = await ApkAnalyzerService.analyzeApk(apkPath);
      
      final analysis = ScamDetector.analyzeApk(apkResult, []);
      
      expect(apkResult.permissions, contains('READ_SMS'));
      expect(apkResult.permissions, contains('SYSTEM_ALERT_WINDOW'));
      expect(analysis.riskScore, greaterThan(30));
    });

    test('3_network_debug.apk should extract URLs but ignore SDK noise', () async {
      final apkPath = '$apkDir/3_network_debug.apk';
      final apkResult = await ApkAnalyzerService.analyzeApk(apkPath);
      
      expect(apkResult.urls, contains('https://example.com/api/login'));
      expect(apkResult.urls, contains('https://firebase.googleapis.com'));
      
      // Should not contain typical binary garbage
      final garbage = apkResult.urls.where((url) => url.contains('\x00'));
      expect(garbage, isEmpty);
    });

    test('4_secrets_debug.apk should detect hardcoded secrets', () async {
      final apkPath = '$apkDir/4_secrets_debug.apk';
      final apkResult = await ApkAnalyzerService.analyzeApk(apkPath);
      
      expect(apkResult.secrets, isNotEmpty);
      expect(
        apkResult.secrets.any((s) => s.contains('AKIAIOSFODNN7EXAMPLE')),
        isTrue,
        reason: 'Should detect AWS key',
      );
      expect(
        apkResult.secrets.any((s) => s.contains('AIzaSyDUMMYKEY1234567890ABCDEFGHIJKLMNO')),
        isTrue,
        reason: 'Should detect Google API key',
      );
    });

    test('5_native_debug.apk should detect native libraries', () async {
      final apkPath = '$apkDir/5_native_debug.apk';
      final apkResult = await ApkAnalyzerService.analyzeApk(apkPath);
      
      expect(apkResult.nativeLibraries, isNotEmpty);
      expect(apkResult.nativeLibraries, contains('lib/arm64-v8a/libdummy.so'));
    });

    test('6_large_debug.apk should parse successfully without crashing', () async {
      final apkPath = '$apkDir/6_large_debug.apk';
      // Just verifying it does not throw OutOfMemory or Timeout
      final apkResult = await ApkAnalyzerService.analyzeApk(apkPath);
      expect(apkResult.md5, isNotEmpty);
    });

    test('DEX structural fingerprint is stable and dex-based', () async {
      final first = await ApkAnalyzerService.analyzeApk('$apkDir/4_secrets_debug.apk');
      final second = await ApkAnalyzerService.analyzeApk('$apkDir/4_secrets_debug.apk');
      expect(first.dexStructuralFingerprint, isNotEmpty);
      expect(first.dexStructuralFingerprint, second.dexStructuralFingerprint);
      expect(first.dexStructuralFingerprint, hasLength(64));
    });
  });
}
