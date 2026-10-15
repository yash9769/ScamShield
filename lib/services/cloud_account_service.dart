// lib/services/cloud_account_service.dart
//
// Client for the server-side account surface (server/accounts.py): sign-in,
// cross-device sync, family protection and the trend feed.
//
// This sits *alongside* AuthService rather than replacing it. The local
// account still gates the app and still works with no network — a scam
// scanner that stops working because a sync server is unreachable would be
// worse than one that never synced. Cloud sign-in is an additive layer that
// unlocks sync and family alerts; everything degrades to local-only when the
// session is absent or the server is down.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CloudAccount {
  final String userId;
  final String email;
  final String? displayName;
  final String authProvider;

  const CloudAccount({
    required this.userId,
    required this.email,
    this.displayName,
    required this.authProvider,
  });
}

class FamilyMember {
  final String userId;
  final String email;
  final String? displayName;
  final String role;
  final bool isYou;

  const FamilyMember({
    required this.userId,
    required this.email,
    this.displayName,
    required this.role,
    required this.isYou,
  });

  String get label => displayName?.isNotEmpty == true ? displayName! : email;

  factory FamilyMember.fromJson(Map<String, dynamic> j) => FamilyMember(
        userId: j['user_id'] ?? '',
        email: j['email'] ?? '',
        displayName: j['display_name'],
        role: j['role'] ?? 'guardian',
        isYou: j['is_you'] == true,
      );
}

class FamilyAlert {
  final String id;
  final String fromDisplay;
  final String? classification;
  final int? riskScore;
  final String? summary;
  final String? createdAt;
  final bool acknowledged;

  const FamilyAlert({
    required this.id,
    required this.fromDisplay,
    this.classification,
    this.riskScore,
    this.summary,
    this.createdAt,
    required this.acknowledged,
  });

  factory FamilyAlert.fromJson(Map<String, dynamic> j) => FamilyAlert(
        id: j['id'] ?? '',
        fromDisplay: j['from_display'] ?? 'A family member',
        classification: j['classification'],
        riskScore: j['risk_score'],
        summary: j['summary'],
        createdAt: j['created_at'],
        acknowledged: j['acknowledged'] == true,
      );
}

class FamilyGroup {
  final String? id;
  final String? name;
  final String? inviteCode;
  final String? role;
  final List<FamilyMember> members;
  final List<FamilyAlert> alerts;

  const FamilyGroup({
    this.id,
    this.name,
    this.inviteCode,
    this.role,
    this.members = const [],
    this.alerts = const [],
  });

  /// The server returns an empty object rather than a 404 when the user has no
  /// group — that's a normal state, not an error.
  bool get exists => id != null && id!.isNotEmpty;

  factory FamilyGroup.fromJson(Map<String, dynamic> j) => FamilyGroup(
        id: j['id'],
        name: j['name'],
        inviteCode: j['invite_code'],
        role: j['role'],
        members: ((j['members'] as List?) ?? [])
            .map((m) => FamilyMember.fromJson(m as Map<String, dynamic>))
            .toList(),
        alerts: ((j['alerts'] as List?) ?? [])
            .map((a) => FamilyAlert.fromJson(a as Map<String, dynamic>))
            .toList(),
      );
}

class TrendItem {
  final String category;
  final int reports;
  final int distinctIndicators;

  const TrendItem({
    required this.category,
    required this.reports,
    required this.distinctIndicators,
  });

  factory TrendItem.fromJson(Map<String, dynamic> j) => TrendItem(
        category: j['category'] ?? 'Uncategorised',
        reports: j['reports'] ?? 0,
        distinctIndicators: j['distinct_indicators'] ?? 0,
      );
}

class ScamTrends {
  final int windowDays;
  final int totalReports;
  final List<TrendItem> trends;

  const ScamTrends({
    required this.windowDays,
    required this.totalReports,
    required this.trends,
  });

  factory ScamTrends.fromJson(Map<String, dynamic> j) => ScamTrends(
        windowDays: j['window_days'] ?? 7,
        totalReports: j['total_reports'] ?? 0,
        trends: ((j['trends'] as List?) ?? [])
            .map((t) => TrendItem.fromJson(t as Map<String, dynamic>))
            .toList(),
      );
}

class LeaderboardEntry {
  final int rank;
  final String displayName;
  final int totalPoints;
  final int streakDays;
  final int badgesEarned;

  /// Marks the signed-in user's own row so the UI can highlight it without
  /// having to match on a name that may not be unique.
  final bool isYou;

  const LeaderboardEntry({
    required this.rank,
    required this.displayName,
    required this.totalPoints,
    required this.streakDays,
    required this.badgesEarned,
    this.isYou = false,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) => LeaderboardEntry(
        rank: j['rank'] ?? 0,
        displayName: j['display_name'] ?? 'ScamShield user',
        totalPoints: j['total_points'] ?? 0,
        streakDays: j['streak_days'] ?? 0,
        badgesEarned: j['badges_earned'] ?? 0,
        isYou: j['is_you'] == true,
      );
}

/// Thrown for a request the caller should surface to the user (bad code,
/// duplicate account, expired session). Network failures are *not* raised as
/// this — they resolve to null/empty so the app keeps working offline.
class CloudException implements Exception {
  final String message;
  const CloudException(this.message);
  @override
  String toString() => message;
}

class CloudAccountService {
  CloudAccountService._();

  static String get _baseUrl {
    const customUrl = String.fromEnvironment('SCAMSHIELD_BACKEND_URL');
    if (customUrl.isNotEmpty) return customUrl;
    return Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://localhost:8000';
  }

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const String _tokenKey = 'scamshield_cloud_token';
  static const String _emailKey = 'scamshield_cloud_email';
  static const String _userIdKey = 'scamshield_cloud_user_id';
  static const Duration _timeout = Duration(seconds: 12);

  /// Lets the UI react the moment a cloud session appears or disappears.
  static final ValueNotifier<bool> signedIn = ValueNotifier<bool>(false);

  static Future<String?> _token() => _storage.read(key: _tokenKey);

  static Future<void> refreshSignedInState() async {
    signedIn.value = (await _token()) != null;
  }

  static Future<CloudAccount?> currentAccount() async {
    final email = await _storage.read(key: _emailKey);
    final userId = await _storage.read(key: _userIdKey);
    if (email == null || userId == null) return null;
    return CloudAccount(userId: userId, email: email, authProvider: 'unknown');
  }

  static Future<Map<String, String>> _authHeaders() async {
    final token = await _token();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Turns a response into decoded JSON, or throws [CloudException] carrying
  /// the server's own message so the UI doesn't have to invent one.
  static Map<String, dynamic> _decode(http.Response resp) {
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    String detail = 'Request failed (${resp.statusCode}).';
    try {
      final body = jsonDecode(resp.body);
      if (body is Map && body['detail'] is String) detail = body['detail'];
    } catch (_) {}
    throw CloudException(detail);
  }

  static Future<void> _storeSession(Map<String, dynamic> data) async {
    await _storage.write(key: _tokenKey, value: data['token'] as String);
    await _storage.write(key: _emailKey, value: data['email'] as String? ?? '');
    await _storage.write(key: _userIdKey, value: data['user_id'] as String? ?? '');
    signedIn.value = true;
  }

  // ── Auth ────────────────────────────────────────────────────────────────

  static Future<void> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final resp = await http
        .post(
          Uri.parse('$_baseUrl/account/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            if (displayName != null) 'display_name': displayName,
          }),
        )
        .timeout(_timeout);
    await _storeSession(_decode(resp));
  }

  static Future<void> login({required String email, required String password}) async {
    final resp = await http
        .post(
          Uri.parse('$_baseUrl/account/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_timeout);
    await _storeSession(_decode(resp));
  }

  static Future<void> signOut() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _userIdKey);
    signedIn.value = false;
  }

  /// Deletes the server-side account and everything hanging off it (synced
  /// scan history, family membership/alerts, push tokens, learning progress —
  /// the server cascades all of it in one statement) and always ends the
  /// local cloud session afterward, whether or not the server call succeeded.
  ///
  /// Always clearing the local session on failure, rather than leaving it
  /// alone so the caller could "retry", is deliberate: a session that survives
  /// an erasure attempt is one an interrupted "delete my data" flow could
  /// leave signed in with no visible trace that anything went wrong, and the
  /// next sync would then re-populate local storage from an account the user
  /// just tried to delete. Recovery if the network call did fail is still
  /// possible — the account still exists server-side, so signing back in
  /// (password or Google) and deleting again reaches the same row.
  ///
  /// Returns true only if the server confirmed deletion. The caller must
  /// still treat local erasure as unconditional — this covers the *server's*
  /// copy only, and its result decides what to tell the user about whether
  /// their cloud-held data specifically was confirmed erased.
  static Future<bool> deleteAccount() async {
    final hadSession = await _token() != null;
    if (!hadSession) return true; // nothing server-side to delete

    var confirmed = false;
    try {
      final resp = await http
          .delete(Uri.parse('$_baseUrl/account'), headers: await _authHeaders())
          .timeout(_timeout);
      confirmed = resp.statusCode == 200;
    } catch (e) {
      debugPrint('CloudAccountService.deleteAccount failed: $e');
      confirmed = false;
    }
    await signOut();
    return confirmed;
  }

  /// Everything the server holds about the signed-in user (DPDP right to
  /// access), for merging into the local "My Data" export. Returns null when
  /// signed out or unreachable — the caller shows that state explicitly
  /// rather than a silently thinner export.
  static Future<Map<String, dynamic>?> exportAccountData() async {
    if (await _token() == null) return null;
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/account/export'), headers: await _authHeaders())
          .timeout(_timeout);
      if (resp.statusCode != 200) return null;
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('CloudAccountService.exportAccountData failed: $e');
      return null;
    }
  }

  // ── Sync ────────────────────────────────────────────────────────────────

  /// Pushes [scans] and returns whatever changed server-side since [since].
  ///
  /// Returns null when there is no cloud session or the server is unreachable
  /// — the caller keeps its local data untouched in that case.
  static Future<Map<String, dynamic>?> syncScans({
    required List<Map<String, dynamic>> scans,
    required double since,
    String? deviceId,
    String? deviceName,
  }) async {
    if (await _token() == null) return null;
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/sync/scans'),
            headers: await _authHeaders(),
            body: jsonEncode({
              'since': since,
              'scans': scans,
              if (deviceId != null) 'device_id': deviceId,
              if (deviceName != null) 'device_name': deviceName,
            }),
          )
          .timeout(_timeout);

      if (resp.statusCode == 401) {
        // The session expired; drop it so the UI stops claiming to be synced.
        await signOut();
        return null;
      }
      return _decode(resp);
    } catch (e) {
      debugPrint('CloudAccountService.syncScans failed: $e');
      return null;
    }
  }

  // ── Family ──────────────────────────────────────────────────────────────

  static Future<FamilyGroup?> fetchFamily() async {
    if (await _token() == null) return null;
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/family'), headers: await _authHeaders())
          .timeout(_timeout);
      if (resp.statusCode == 401) {
        await signOut();
        return null;
      }
      return FamilyGroup.fromJson(_decode(resp));
    } catch (e) {
      debugPrint('CloudAccountService.fetchFamily failed: $e');
      return null;
    }
  }

  static Future<FamilyGroup> createFamily(String name) async {
    final resp = await http
        .post(
          Uri.parse('$_baseUrl/family/create'),
          headers: await _authHeaders(),
          body: jsonEncode({'name': name}),
        )
        .timeout(_timeout);
    return FamilyGroup.fromJson(_decode(resp));
  }

  static Future<FamilyGroup> joinFamily(String inviteCode, {String role = 'guardian'}) async {
    final resp = await http
        .post(
          Uri.parse('$_baseUrl/family/join'),
          headers: await _authHeaders(),
          body: jsonEncode({'invite_code': inviteCode, 'role': role}),
        )
        .timeout(_timeout);
    return FamilyGroup.fromJson(_decode(resp));
  }

  static Future<void> leaveFamily() async {
    final resp = await http
        .post(Uri.parse('$_baseUrl/family/leave'), headers: await _authHeaders())
        .timeout(_timeout);
    _decode(resp);
  }

  /// Relays a high-risk verdict to the family. Best-effort: a failure here
  /// must never interrupt the scan the user actually asked for.
  static Future<bool> raiseAlert({
    required String classification,
    required int riskScore,
    required String summary,
  }) async {
    if (await _token() == null) return false;
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/family/alert'),
            headers: await _authHeaders(),
            body: jsonEncode({
              'classification': classification,
              'risk_score': riskScore,
              'summary': summary,
            }),
          )
          .timeout(_timeout);
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('CloudAccountService.raiseAlert failed: $e');
      return false;
    }
  }

  static Future<void> acknowledgeAlert(String alertId) async {
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/family/alert/$alertId/ack'),
            headers: await _authHeaders(),
          )
          .timeout(_timeout);
    } catch (e) {
      debugPrint('CloudAccountService.acknowledgeAlert failed: $e');
    }
  }

  // ── Push tokens ─────────────────────────────────────────────────────────

  /// Tells the server which device to wake for this account's family alerts.
  /// Silent no-op when signed out — push is a convenience layered on top of
  /// the alert record, never the thing that carries it.
  static Future<bool> registerPushToken(String token) async {
    if (await _token() == null) return false;
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/push/register'),
            headers: await _authHeaders(),
            body: jsonEncode({'token': token, 'platform': 'android'}),
          )
          .timeout(_timeout);
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('CloudAccountService.registerPushToken failed: $e');
      return false;
    }
  }

  /// Called on sign-out. Without this a shared or handed-on phone would keep
  /// receiving the previous account's family alerts.
  static Future<void> unregisterPushToken(String token) async {
    try {
      await http
          .delete(
            Uri.parse('$_baseUrl/push/register'),
            headers: await _authHeaders(),
            body: jsonEncode({'token': token, 'platform': 'android'}),
          )
          .timeout(_timeout);
    } catch (e) {
      debugPrint('CloudAccountService.unregisterPushToken failed: $e');
    }
  }

  // ── Learning progress & leaderboard ─────────────────────────────────────

  static Future<bool> pushLearningProgress({
    required int totalPoints,
    required int streakDays,
    required int badgesEarned,
    required int quizzesPassed,
    required int articlesRead,
  }) async {
    if (await _token() == null) return false;
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/learning/progress'),
            headers: await _authHeaders(),
            body: jsonEncode({
              'total_points': totalPoints,
              'streak_days': streakDays,
              'badges_earned': badgesEarned,
              'quizzes_passed': quizzesPassed,
              'articles_read': articlesRead,
            }),
          )
          .timeout(_timeout);
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('CloudAccountService.pushLearningProgress failed: $e');
      return false;
    }
  }

  /// [scope] is 'global' or 'family'. Returns null on any failure so the UI
  /// can say "couldn't load" rather than render a confidently empty board.
  static Future<List<LeaderboardEntry>?> fetchLeaderboard({
    String scope = 'global',
  }) async {
    if (await _token() == null) return null;
    try {
      final resp = await http
          .get(
            Uri.parse('$_baseUrl/learning/leaderboard?scope=$scope'),
            headers: await _authHeaders(),
          )
          .timeout(_timeout);
      final data = _decode(resp);
      return (data['entries'] as List<dynamic>? ?? [])
          .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('CloudAccountService.fetchLeaderboard failed: $e');
      return null;
    }
  }

  // ── Trends ──────────────────────────────────────────────────────────────

  /// The trend feed is public — no session needed — so it still has something
  /// to show a user who has never signed in.
  static Future<ScamTrends?> fetchTrends({int days = 7}) async {
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/trends?days=$days'))
          .timeout(_timeout);
      return ScamTrends.fromJson(_decode(resp));
    } catch (e) {
      debugPrint('CloudAccountService.fetchTrends failed: $e');
      return null;
    }
  }
}
