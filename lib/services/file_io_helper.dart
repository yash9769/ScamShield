// lib/services/file_io_helper.dart
// Web-safe dart:io wrapper using conditional imports.
// On web: all methods return safe defaults (stub).
// On native: delegates to dart:io File.

// Re-export FileIoHelper from the selected implementation
export 'file_io_helper_stub.dart'
    if (dart.library.io) 'file_io_helper_native.dart';
