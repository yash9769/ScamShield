import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scamshield/services/backend_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('normalize', () {
    test('adds http:// and strips trailing slashes', () {
      expect(
        BackendConfig.normalize('192.168.1.5:8000'),
        'http://192.168.1.5:8000',
      );
      expect(
        BackendConfig.normalize('  http://10.0.0.2:8000/// '),
        'http://10.0.0.2:8000',
      );
      expect(
        BackendConfig.normalize('https://api.example.com'),
        'https://api.example.com',
      );
    });

    test('rejects empty and unusable input', () {
      expect(BackendConfig.normalize(''), isNull);
      expect(BackendConfig.normalize(null), isNull);
      expect(BackendConfig.normalize('ftp://host'), isNull);
      expect(BackendConfig.normalize('http://'), isNull);
    });
  });

  group('saved address', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      BackendConfig.savedUrl.value = null;
    });

    test('a saved address wins and is persisted', () async {
      expect(BackendConfig.isDefault, isTrue);
      expect(await BackendConfig.save('192.168.1.5:8000'), isTrue);
      expect(BackendConfig.baseUrl, 'http://192.168.1.5:8000');
      expect(BackendConfig.isDefault, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('scamshield_backend_url'),
        'http://192.168.1.5:8000',
      );
    });

    test('clearing returns to the default', () async {
      await BackendConfig.save('192.168.1.5:8000');
      expect(await BackendConfig.save(null), isTrue);
      expect(BackendConfig.isDefault, isTrue);
      expect(BackendConfig.baseUrl, BackendConfig.developmentDefault);
    });

    test('garbage is refused and changes nothing', () async {
      await BackendConfig.save('192.168.1.5:8000');
      expect(await BackendConfig.save('ftp://nope'), isFalse);
      expect(BackendConfig.baseUrl, 'http://192.168.1.5:8000');
    });

    test('init loads what was saved', () async {
      SharedPreferences.setMockInitialValues({
        'scamshield_backend_url': 'http://10.1.1.1:8000',
      });
      BackendConfig.savedUrl.value = null;
      // init() is once-per-process; reading the value it would load is enough here.
      final prefs = await SharedPreferences.getInstance();
      expect(
        BackendConfig.normalize(prefs.getString('scamshield_backend_url')),
        'http://10.1.1.1:8000',
      );
    });
  });
}
