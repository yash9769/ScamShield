// test/backend_config_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:scamshield/services/backend_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackendConfig.baseUrl', () {
    test('returns the injected override when provided', () {
      // SCAMSHIELD_BACKEND_URL is a const String.fromEnvironment, so it cannot
      // be changed at runtime. Without a define it falls back to a dev URL.
      if (BackendConfig.backendUrlOverride.isNotEmpty) {
        expect(BackendConfig.baseUrl, BackendConfig.backendUrlOverride);
      }
    });

    test('never returns a URL with a trailing slash', () {
      expect(BackendConfig.baseUrl.endsWith('/'), isFalse);
    });
  });

  group('BackendConfig.validate', () {
    test('does not throw in debug/profile runs', () {
      // Tests run outside release mode, so validate() is a no-op unless a
      // non-https override was somehow injected.
      try {
        BackendConfig.validate();
      } on StateError {
        // Only reachable when the test build defines a bad URL — then the
        // failure is legitimate and worth surfacing.
        rethrow;
      }
    });
  });
}
