import 'package:flutter/foundation.dart';

/// Simple app-wide signal so screens can refresh when transactions change
/// (SMS sync, manual add, category edit).
class AppEvents {
  static final ValueNotifier<int> transactionsChanged = ValueNotifier<int>(0);

  static void notifyTransactionsChanged() => transactionsChanged.value++;
}