// lib/services/share_intent_service.dart
//
// App-wide "content was shared into ScamShield from another app" signal.
//
// Mirrors the pattern in data_change_notifier.dart: MainNavigation keeps
// every tab alive inside an IndexedStack, so we can't just "navigate to
// ScanScreen with an argument" the way a fresh route push would work.
// Instead this exposes a ValueNotifier that both MainNavigation (to switch
// to the Scan tab) and ScanScreen (to actually consume the content) listen
// to independently.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

enum SharedScanKind { text, image }

class SharedScanRequest {
  final SharedScanKind kind;
  final String value; // shared text/URL, or the on-disk path for an image
  const SharedScanRequest({required this.kind, required this.value});
}

class ShareIntentService {
  ShareIntentService._();

  static final ValueNotifier<SharedScanRequest?> pending =
      ValueNotifier<SharedScanRequest?>(null);

  static StreamSubscription<List<SharedMediaFile>>? _subscription;
  static bool _initialized = false;

  /// Starts listening for share-intent content. Safe to call multiple times
  /// (e.g. if MainNavigation is rebuilt) — only wires the listener once.
  static void init() {
    if (_initialized) return;
    _initialized = true;

    // Shared content arriving while the app is already running.
    _subscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handle,
      onError: (Object _) {},
    );

    // Shared content that launched the app from a cold start.
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _handle(files);
      ReceiveSharingIntent.instance.reset();
    });
  }

  static void _handle(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    final file = files.first;
    switch (file.type) {
      case SharedMediaType.text:
      case SharedMediaType.url:
        if (file.path.trim().isEmpty) return;
        pending.value = SharedScanRequest(kind: SharedScanKind.text, value: file.path.trim());
        break;
      case SharedMediaType.image:
        pending.value = SharedScanRequest(kind: SharedScanKind.image, value: file.path);
        break;
      case SharedMediaType.video:
      case SharedMediaType.file:
        // Not a scan target we support today (see AndroidManifest.xml —
        // we only register SEND filters for text/* and image/*).
        break;
    }
  }

  /// Clears the pending request once a listener has handled it, so the same
  /// content isn't reprocessed when other listeners rebuild or a tab switch
  /// happens.
  static void consume() => pending.value = null;
}
