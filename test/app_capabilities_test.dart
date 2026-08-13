// test/app_capabilities_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/services/app_capabilities_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppCapabilities tests', () {
    test('AppCapabilities.offline provides accurate default offline flags', () {
      const caps = AppCapabilities.offline;
      expect(caps.isBackendReachable, isFalse);
      expect(caps.hasFullAi, isFalse);
      expect(caps.hasOsint, isFalse);
      expect(caps.hasFullApkPipeline, isFalse);
      expect(caps.isOfflineMode, isTrue);
      expect(caps.modeLabel, contains('Limited Mode'));
    });

    test('AppCapabilitiesValueNotifier initializes with offline state', () {
      expect(AppCapabilitiesService.capabilities.value.isOfflineMode, isTrue);
      expect(AppCapabilitiesService.capabilities.value.hasFullAi, isFalse);
    });
  });
}
