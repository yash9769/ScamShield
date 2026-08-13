import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class ApkAnalysisResult {
  final String md5;
  final String sha1;
  final String sha256;

  /// DEX structural fingerprint: SHA-256 over dex entry names + contents in
  /// zip order. This is an EXACT fingerprint, not fuzzy similarity — any
  /// significant dex change yields a different hash. Two APKs built from the
  /// same dex bodies share it even when re-signed with a different cert, so
  /// repackaged scam apps can be matched exactly.
  final String dexStructuralFingerprint;

  /// Simplified structural/fuzzy hash: min-hash over 4-grams of all dex
  /// content combined. Different from sha256 — two variants of the same app
  /// with minor code tweaks will have similar (but not identical) min-hashes,
  /// while completely different APKs will diverge. Used for similarity lookup.
  final String dexMinHash;

  final List<String> permissions;
  final List<String> urls;
  final List<String> secrets;
  final List<String> nativeLibraries;
  final List<String> certificates;
  final Map<String, String> metadata;

  /// Dangerous framework API patterns found in classes*.dex.
  final List<String> dangerousApis;

  /// Weighted risk score from dangerous permissions alone (0–100).
  final int permissionRiskScore;

  /// Human-readable assessment of the certificate (e.g. "Debug key", "Trusted").
  final String certificateReputation;

  /// Risk contribution from certificate (0–30).
  final int certificateRiskScore;

  /// Overall on-device risk score (0–100), combining permissions, dangerous
  /// APIs, secrets, certificate, and native libs.
  final int onDeviceRiskScore;

  /// Severity label derived from onDeviceRiskScore.
  final String onDeviceRiskLevel;

  ApkAnalysisResult({
    required this.md5,
    required this.sha1,
    required this.sha256,
    required this.dexStructuralFingerprint,
    required this.dexMinHash,
    required this.permissions,
    required this.urls,
    required this.secrets,
    required this.nativeLibraries,
    required this.certificates,
    required this.metadata,
    required this.dangerousApis,
    required this.permissionRiskScore,
    required this.certificateReputation,
    required this.certificateRiskScore,
    required this.onDeviceRiskScore,
    required this.onDeviceRiskLevel,
  });
}

/// Risk weights for Android dangerous permissions.
/// Scores are additive and capped at 100 for the permissionRiskScore.
const Map<String, int> _permissionWeights = {
  'INSTALL_PACKAGES': 40,
  'REQUEST_INSTALL_PACKAGES': 35,
  'BIND_ACCESSIBILITY_SERVICE': 35,
  'SYSTEM_ALERT_WINDOW': 30,
  'READ_SMS': 25,
  'RECEIVE_SMS': 20,
  'SEND_SMS': 20,
  'READ_CALL_LOG': 20,
  'WRITE_CALL_LOG': 20,
  'PROCESS_OUTGOING_CALLS': 15,
  'READ_CONTACTS': 15,
  'RECORD_AUDIO': 15,
  'CAMERA': 10,
  'ACCESS_FINE_LOCATION': 10,
  'ACCESS_BACKGROUND_LOCATION': 15,
  'READ_EXTERNAL_STORAGE': 5,
  'WRITE_EXTERNAL_STORAGE': 5,
  'GET_ACCOUNTS': 10,
  'USE_BIOMETRIC': 5,
  'USE_FINGERPRINT': 5,
};

/// Byte patterns (as ASCII substrings) for dangerous framework API usage,
/// kept in sync with backend/app/analyzers/androguard_analyzer.py.
const List<Map<String, List<String>>> _dexPatterns = [
  {
    'accessibility_abuse': [
      'Landroid/accessibilityservice/AccessibilityService;',
      'AccessibilityNodeInfo',
      'performAction',
      'dispatchGesture',
    ],
  },
  {
    'sms_stealing': [
      'Landroid/telephony/SmsManager;',
      'Landroid/provider/Telephony\$Sms;',
      'SMS_RECEIVED',
    ],
  },
  {
    'call_recording': ['MediaRecorder', 'VOICE_CALL', 'getCallState'],
  },
  {
    'dynamic_code_loading': [
      'Ldalvik/system/DexClassLoader;',
      'Ldalvik/system/InMemoryDexClassLoader;',
      'System.loadLibrary',
    ],
  },
  {
    'rooting_hooks': ['Landroid/os/Runtime;', 'su -c', 'Magisk', 'mount -o remount'],
  },
  {
    'anti_analysis': ['isDebuggerConnected', 'getInstallerPackageName'],
  },
  {
    'background_mic': ['setAudioSource', 'VOICE_RECOGNITION'],
  },
  {
    'device_id_collection': ['getDeviceId', 'getImei', 'getSubscriberId'],
  },
  {
    'credential_harvesting': ['addJavascriptInterface', 'setOnKeyListener'],
  },
  {
    'remote_command': ['java.lang.Process', 'Runtime.getRuntime', 'ProcessBuilder'],
  },
];


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
    final dangerousApis = <String>{};

    // DEX structural fingerprint: SHA-256 of dex entry names + contents, in
    // zip order. Only dex entries are fingerprinted so re-signing the APK
    // (which changes META-INF) does not alter the fingerprint.
    final fingerprintBuilder = BytesBuilder(copy: false);

    for (final file in archive) {
      if (!file.isFile) continue;

      final isDex = file.name.endsWith('.dex');

      if (isDex) {
        fingerprintBuilder.add(utf8.encode(file.name));
        fingerprintBuilder.add(file.content as List<int>);
      }

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

      // d. classes.dex & native libs for URLs, Secrets, and dangerous APIs
      if (file.name.endsWith('.dex') || file.name.endsWith('.so') || file.name.endsWith('.bin')) {
        try {
          final contentBytes = file.content as List<int>;
          final strings = _extractPrintableStrings(contentBytes);

          // Detect dangerous framework API patterns in dex content.
          if (isDex) {
            for (final group in _dexPatterns) {
              for (final entry in group.entries) {
                if (dangerousApis.contains(entry.key)) continue;
                for (final pattern in entry.value) {
                  for (final s in strings) {
                    if (s.contains(pattern)) {
                      dangerousApis.add(entry.key);
                      break;
                    }
                  }
                  if (dangerousApis.contains(entry.key)) break;
                }
              }
            }
          }
          
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

    final dexBytes = fingerprintBuilder.takeBytes();
    final dexStructuralFingerprint = sha256.convert(dexBytes).toString();
    final dexMinHash = _computeDexMinHash(dexBytes);

    // ── Permission risk score ─────────────────────────────────────────────────
    int permScore = 0;
    for (final perm in permissions) {
      permScore += _permissionWeights[perm] ?? 0;
    }
    final permissionRiskScore = permScore.clamp(0, 100);

    // ── Certificate reputation ────────────────────────────────────────────────
    String certReputation = 'Unknown';
    int certRiskScore = 0;
    final certStrings = certificates.join(' ').toLowerCase();
    if (certStrings.contains('debug') || certStrings.contains('androiddebugkey')) {
      certReputation = 'Debug key (high risk — debug-signed APKs should never be distributed)';
      certRiskScore = 30;
    } else if (certStrings.contains('cn=android') ||
        certStrings.contains('cn=test') ||
        certStrings.contains('o=example')) {
      certReputation = 'Generic / self-signed (medium risk — likely not from a reputable publisher)';
      certRiskScore = 15;
    } else if (certStrings.contains('.sf') || certStrings.isEmpty) {
      certReputation = 'Certificate unreadable or absent (suspicious)';
      certRiskScore = 20;
    } else {
      certReputation = 'Custom publisher certificate (review CN/O fields for trust)';
      certRiskScore = 0;
    }

    // ── Dangerous API score ───────────────────────────────────────────────────
    // Each dangerous API pattern contributes 10 points (capped at 40).
    final apiScore = (dangerousApis.length * 10).clamp(0, 40);

    // ── Secrets score ─────────────────────────────────────────────────────────
    final secretScore = (secrets.length * 10).clamp(0, 20);

    // ── Combined on-device score ──────────────────────────────────────────────
    final rawScore = (permissionRiskScore * 0.4 +
        apiScore * 0.35 +
        certRiskScore * 0.15 +
        secretScore * 0.10).round();
    final onDeviceRiskScore = rawScore.clamp(0, 100);

    String onDeviceRiskLevel;
    if (onDeviceRiskScore >= 80) {
      onDeviceRiskLevel = 'CRITICAL';
    } else if (onDeviceRiskScore >= 60) {
      onDeviceRiskLevel = 'HIGH';
    } else if (onDeviceRiskScore >= 30) {
      onDeviceRiskLevel = 'MEDIUM';
    } else if (onDeviceRiskScore >= 1) {
      onDeviceRiskLevel = 'LOW';
    } else {
      onDeviceRiskLevel = 'SAFE';
    }

    return ApkAnalysisResult(
      md5: md5Hash,
      sha1: sha1Hash,
      sha256: sha256Hash,
      dexStructuralFingerprint: dexStructuralFingerprint,
      dexMinHash: dexMinHash,
      permissions: permissions.toList(),
      urls: urls.toList(),
      secrets: secrets.toList(),
      nativeLibraries: nativeLibraries,
      certificates: certificates.toSet().toList(),
      metadata: metadata,
      dangerousApis: dangerousApis.toList(),
      permissionRiskScore: permissionRiskScore,
      certificateReputation: certReputation,
      certificateRiskScore: certRiskScore,
      onDeviceRiskScore: onDeviceRiskScore,
      onDeviceRiskLevel: onDeviceRiskLevel,
    );
  }

  /// Simplified min-hash over 4-grams of dex content for fuzzy/structural
  /// similarity. We use 32 independent hash functions (bit shifts of a FNV-1a
  /// seed) and keep the minimum value for each, then hex-encode the result.
  /// This is fast, pure-Dart, and gives a 32-byte fingerprint suitable for
  /// approximate similarity comparison.
  static String _computeDexMinHash(List<int> bytes) {
    if (bytes.isEmpty) return '0' * 64;

    const nHashes = 32;
    final mins = List<int>.filled(nHashes, 0x7fffffffffffffff);

    for (int i = 0; i < bytes.length - 3; i++) {
      // FNV-1a 64-bit (approximated in Dart's 64-bit int)
      int h = 0xcbf29ce484222325;
      h ^= bytes[i];
      h = (h * 0x100000001b3) & 0x7fffffffffffffff;
      h ^= bytes[i + 1];
      h = (h * 0x100000001b3) & 0x7fffffffffffffff;
      h ^= bytes[i + 2];
      h = (h * 0x100000001b3) & 0x7fffffffffffffff;
      h ^= bytes[i + 3];
      h = (h * 0x100000001b3) & 0x7fffffffffffffff;

      for (int j = 0; j < nHashes; j++) {
        final hj = (h ^ (h >> (j + 1))) & 0x7fffffffffffffff;
        if (hj < mins[j]) mins[j] = hj;
      }
    }

    return mins.map((v) => v.toRadixString(16).padLeft(8, '0')).join();
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

