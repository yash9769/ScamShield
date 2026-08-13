// Smoke test: the ScamShield app boots and shows the home screen.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scamshield/main.dart';

// 1x1 transparent PNG served for every image request in tests (the default
// test HTTP client returns 400 for all requests, which would otherwise throw
// a NetworkImageLoadException before the widget's error listener attaches).
final Uint8List _kTransparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _FakeHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpRequest();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _FakeHttpRequest();
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpRequest implements HttpClientRequest {
  final HttpHeaders _headers = _FakeHeaders();
  @override
  HttpHeaders get headers => _headers;
  @override
  Future<HttpClientResponse> close() async => _FakeResponse();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;
  @override
  int get contentLength => _kTransparentPng.length;
  @override
  String get reasonPhrase => 'OK';
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  HttpHeaders get headers => _FakeHeaders();
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_kTransparentPng]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets('App boots and shows the home screen', (WidgetTester tester) async {
    HttpOverrides.global = _FakeHttpOverrides();
    addTearDown(() => HttpOverrides.global = null);

    await tester.pumpWidget(const ScamShieldApp(startLoggedIn: true));
    // Pump a few frames rather than settle — the app schedules clipboard /
    // stats refresh timers that would keep pumpAndSettle busy forever.
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('ScamShield'), findsWidgets);
    expect(find.byType(Scaffold), findsWidgets);
  });
}
