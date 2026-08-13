import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/services/file_scanner_service.dart';
import 'package:scamshield/services/settings_service.dart';
import 'package:scamshield/services/scam_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Clipboard Scan Settings Tests', () {
    test('does not read clipboard if autoScanClipboard is disabled', () async {
      SettingsService.autoScanClipboard.value = false;

      bool clipboardAccessed = false;
      // Register mock handler to capture clipboard access attempts
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
        if (methodCall.method == 'Clipboard.getData') {
          clipboardAccessed = true;
          return {'text': 'URGENT scam link bit.ly/lottery'};
        }
        return null;
      });

      final result = await FileScannerService.scanClipboard();

      expect(result, isNotNull);
      expect(result!.rawContent, isEmpty);
      expect(result.error, contains('disabled in settings'));
      expect(clipboardAccessed, isFalse);
    });

    test('reads clipboard if autoScanClipboard is enabled', () async {
      SettingsService.autoScanClipboard.value = true;

      bool clipboardAccessed = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
        if (methodCall.method == 'Clipboard.getData') {
          clipboardAccessed = true;
          return {'text': 'Safe message here'};
        }
        return null;
      });

      final result = await FileScannerService.scanClipboard();

      expect(result, isNotNull);
      expect(clipboardAccessed, isTrue);
      expect(result!.rawContent, 'Safe message here');
      expect(result.analysis.classification, ScamClassification.safe);
    });
  });
}
