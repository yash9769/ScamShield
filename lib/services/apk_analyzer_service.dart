import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class ApkAnalysisResult {
  final String md5;
  final String sha1;
  final String sha256;
  final List<String> permissions;
  final List<String> urls;
  final List<String> secrets;
  final List<String> nativeLibraries;
  final List<String> certificates;
  final Map<String, String> metadata;

  ApkAnalysisResult({
    required this.md5,
    required this.sha1,
    required this.sha256,
    required this.permissions,
    required this.urls,
    required this.secrets,
    required this.nativeLibraries,
    required this.certificates,
    required this.metadata,
  });
}

class ApkAnalyzerService {
  /// Runs the heavy analysis in an isolate to avoid blocking the UI.
  static Future<ApkAnalysisResult> analyzeApk(String filePath) async {
    return compute(_analyzeApkTask, filePath);
  }

  static Future<ApkAnalysisResult> _analyzeApkTask(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();

    // 1. Compute Hashes
    final md5Hash = md5.convert(bytes).toString();
    final sha1Hash = sha1.convert(bytes).toString();
    final sha256Hash = sha256.convert(bytes).toString();

    // 2. Decode Zip (with error handling for corrupt/password zips)
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw Exception('Invalid or corrupted APK file. Could not read ZIP archive. Ensure it is a valid APK and not password-protected.');
    }

    if (archive.isEmpty) {
      throw Exception('The APK is empty.');
    }

    final permissions = <String>{};
    final urls = <String>{};
    final secrets = <String>{};
    final nativeLibraries = <String>[];
    final certificates = <String>[];
    final metadata = <String, String>{};

    for (final file in archive) {
      if (!file.isFile) continue;

      // a. Native Libraries
      if (file.name.startsWith('lib/')) {
        nativeLibraries.add(file.name);
      }

      // b. Certificates
      if (file.name.startsWith('META-INF/') && 
          (file.name.endsWith('.RSA') || file.name.endsWith('.DSA') || file.name.endsWith('.SF'))) {
        certificates.add(file.name);
        try {
          final certBytes = file.content as List<int>;
          final certStrings = _extractPrintableStrings(certBytes);
          for (final s in certStrings) {
            // Rough heuristic for subjects/issuers
            if (s.contains('CN=') || s.contains('O=') || s.contains('OU=')) {
              if (s.length < 200) certificates.add('Cert Details: $s');
            }
          }
        } catch (_) {}
      }

      // c. AndroidManifest.xml (Permissions & Metadata)
      if (file.name == 'AndroidManifest.xml') {
        try {
          final manifestBytes = file.content as List<int>;
          final manifestStrings = _extractPrintableStrings(manifestBytes);
          
          for (final s in manifestStrings) {
            // Permissions
            final permRegex = RegExp(r'android\.permission\.([A-Z_]+)');
            for (final m in permRegex.allMatches(s)) {
              final perm = m.group(1);
              if (perm != null && !permissions.contains(perm)) {
                permissions.add(perm);
              }
            }
            // Approximation for package name (usually com.something.something)
            if (s.startsWith('com.') && s.split('.').length >= 3 && !s.contains('/')) {
              if (!metadata.containsKey('Package')) {
                metadata['Package'] = s;
              }
            }
          }
        } catch (_) {}
      }

      // d. classes.dex & native libs for URLs and Secrets
      if (file.name.endsWith('.dex') || file.name.endsWith('.so') || file.name.endsWith('.bin')) {
        try {
          final contentBytes = file.content as List<int>;
          final strings = _extractPrintableStrings(contentBytes);
          
          // Regexes for URLs and Secrets
          final urlRegex = RegExp(r'https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}[/\w.-]*');
          final ignoreDomains = {
            'developer.android.com', 'github.com', 'w3.org', 'flutter.dev',
            'apache.org', 'adobe.com', 'apple.com', 'google.com', 'fonts.googleapis.com',
            'schemas.android.com', 'ns.adobe.com', 'youtrack.jetbrains.com',
            'kotlinlang.org', 'java.sun.com', 'xmlpull.org', 'play.google.com',
            'plus.google.com', 'fonts.gstatic.com', 'www.w3.org', 'www.google.com',
          };
          
          final awsKeyRegex = RegExp(r'(AKIA[0-9A-Z]{16})');
          final googleApiKeyRegex = RegExp(r'(AIza[0-9A-Za-z-_]{35})');
          final stripeKeyRegex = RegExp(r'((?:sk|pk)_(?:test|live)_[0-9a-zA-Z]{24})');
          final supabaseUrlRegex = RegExp(r'(https://[a-zA-Z0-9-]+\.supabase\.co)');
          final jwtRegex = RegExp(r'(eyJ[a-zA-Z0-9_-]+\.eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+)');
          
          for (final s in strings) {
            // Check URLs
            final urlMatches = urlRegex.allMatches(s);
            for (final m in urlMatches) {
              final url = m.group(0);
              if (url != null) {
                final uri = Uri.tryParse(url);
                if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
                  if (!ignoreDomains.contains(uri.host)) {
                    urls.add(url);
                  }
                }
              }
            }
            
            // Check Secrets
            if (awsKeyRegex.hasMatch(s)) secrets.add('AWS Key: ${awsKeyRegex.firstMatch(s)?.group(0)}');
            if (googleApiKeyRegex.hasMatch(s)) secrets.add('Google API Key: ${googleApiKeyRegex.firstMatch(s)?.group(0)}');
            if (stripeKeyRegex.hasMatch(s)) secrets.add('Stripe Key: ${stripeKeyRegex.firstMatch(s)?.group(0)}');
            if (supabaseUrlRegex.hasMatch(s)) secrets.add('Supabase URL: ${supabaseUrlRegex.firstMatch(s)?.group(0)}');
            if (jwtRegex.hasMatch(s)) secrets.add('JWT Token: ${jwtRegex.firstMatch(s)?.group(0)}');
            if (s.toLowerCase().contains('bearer ') && s.length > 20) {
               // Heuristic for hardcoded bearer tokens
               if (!s.contains(' ') || s.split(' ').length <= 3) {
                 secrets.add('Possible Bearer Token: $s');
               }
            }
          }
        } catch (_) {}
      }
    }

    return ApkAnalysisResult(
      md5: md5Hash,
      sha1: sha1Hash,
      sha256: sha256Hash,
      permissions: permissions.toList(),
      urls: urls.toList(),
      secrets: secrets.toList(),
      nativeLibraries: nativeLibraries,
      certificates: certificates.toSet().toList(),
      metadata: metadata,
    );
  }

  /// Extracts printable ASCII strings (length >= 5) from a raw byte buffer.
  static List<String> _extractPrintableStrings(List<int> bytes) {
    final strings = <String>[];
    final buffer = StringBuffer();
    
    for (int i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b == 0) continue; // Ignore null bytes to merge UTF-16LE characters
      
      // Basic printable ASCII range
      if (b >= 32 && b <= 126) {
        buffer.writeCharCode(b);
      } else {
        if (buffer.length >= 5) {
          strings.add(buffer.toString());
        }
        buffer.clear();
      }
    }
    if (buffer.length >= 5) {
      strings.add(buffer.toString());
    }
    return strings;
  }
}
