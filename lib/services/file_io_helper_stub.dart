// lib/services/file_io_helper_stub.dart
// Web stub — dart:io is unavailable on web.

import 'dart:typed_data';

class FileIoHelper {
  static bool get isAndroid => false;
  static bool get isIOS => false;

  static Future<Uint8List> readBytes(String path) async => Uint8List(0);
}
