// lib/services/file_io_helper_native.dart
// Native implementation — dart:io is available on Android/iOS/Desktop.

import 'dart:io';
import 'dart:typed_data';

class FileIoHelper {
  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;

  static Future<Uint8List> readBytes(String path) async {
    return File(path).readAsBytes();
  }
}
