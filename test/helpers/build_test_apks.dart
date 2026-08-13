// test/helpers/build_test_apks.dart
// Builds the fixture APKs used by test/apk_analyzer_test.dart into
// ScamShield_Test_APKs/ (gitignored). Fixtures are generated at test time so
// no binaries need to be committed.
//
// The analyzer reads manifest / dex content as printable strings, so a
// text-based ZIP with the right file names is a sufficient fixture.

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const fixtureDir = 'ScamShield_Test_APKs';

void _writeZip(String name, List<(String, Uint8List)> entries) {
  final archive = Archive();
  for (final entry in entries) {
    archive.addFile(
      ArchiveFile(entry.$1, entry.$2.length, entry.$2),
    );
  }
  final bytes = ZipEncoder().encode(archive);
  File('$fixtureDir/$name').writeAsBytesSync(bytes);
}

Uint8List _text(String s) => Uint8List.fromList(s.codeUnits);

Future<void> ensureFixtures() async {
  await Directory(fixtureDir).create(recursive: true);

  // 1. Benign — only INTERNET permission, clean dex.
  _writeZip('1_benign_debug.apk', [
    ('AndroidManifest.xml', _text('<uses-permission android:name="android.permission.INTERNET"/>')),
    ('classes.dex', _text('public class Main { public void onCreate() { } }')),
  ]);

  // 2. Dangerous permissions — READ_SMS + overlay access.
  _writeZip('2_permissions_debug.apk', [
    (
      'AndroidManifest.xml',
      _text(
        '<uses-permission android:name="android.permission.READ_SMS"/>'
        '<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>',
      ),
    ),
    ('classes.dex', _text('public class Main { }')),
  ]);

  // 3. Network endpoints.
  _writeZip('3_network_debug.apk', [
    ('AndroidManifest.xml', _text('<uses-permission android:name="android.permission.INTERNET"/>')),
    (
      'classes.dex',
      _text('apiClient.baseUrl = "https://example.com/api/login"; firebaseEndpoint = "https://firebase.googleapis.com";'),
    ),
  ]);

  // 4. Hardcoded secrets (valid-length AWS + Google keys).
  _writeZip('4_secrets_debug.apk', [
    ('AndroidManifest.xml', _text('<uses-permission android:name="android.permission.INTERNET"/>')),
    (
      'classes.dex',
      _text('awsKey="AKIAIOSFODNN7EXAMPLE"; googleKey="AIzaSyDUMMYKEY1234567890ABCDEFGHIJKLMNO";'),
    ),
  ]);

  // 5. Native library.
  _writeZip('5_native_debug.apk', [
    ('AndroidManifest.xml', _text('<uses-permission android:name="android.permission.INTERNET"/>')),
    ('classes.dex', _text('public class Main { }')),
    ('lib/arm64-v8a/libdummy.so', Uint8List.fromList(List.filled(64, 1))),
  ]);

  // 6. Large filler APK.
  _writeZip('6_large_debug.apk', [
    ('AndroidManifest.xml', _text('<uses-permission android:name="android.permission.INTERNET"/>')),
    ('classes.dex', _text('public class Main { }')),
    ('res/filler.bin', Uint8List.fromList(List<int>.generate(8 * 1024 * 1024, (i) => i % 251))),
  ]);
}
