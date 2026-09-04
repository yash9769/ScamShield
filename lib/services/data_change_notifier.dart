// lib/services/data_change_notifier.dart
//
// App-wide "scan data changed" signal.
//
// MainNavigation (lib/main.dart) keeps every bottom-nav tab alive inside an
// IndexedStack, so Home/History/Profile only run their initState() once, at
// app launch — switching tabs does not rebuild them or re-query SQLite.
// That's fine for normal use, but it means a deletion made from a DIFFERENT
// screen instance (Settings > Privacy & Data > Delete My Data / Delete
// Account, or a scan saved from the Scan tab) would leave an
// already-visited History/Home/Profile tab silently showing stale data —
// visually indistinguishable from the deletion not having worked, which is
// exactly the wrong failure mode for a privacy control.
//
// ScanRepository fires this notifier after every mutation (save/delete/
// clear/retention-cleanup); screens that display scan-derived data listen
// for it and reload.
import 'package:flutter/foundation.dart';

class DataChangeNotifier {
  DataChangeNotifier._();

  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static void notifyChanged() => version.value++;
}
