import 'package:flutter/foundation.dart';

/// Simple app-wide signal so screens can refresh when transactions change
/// (SMS sync, manual add, category edit).
class AppEvents {
  static final ValueNotifier<int> transactionsChanged = ValueNotifier<int>(0);

  static void notifyTransactionsChanged() => transactionsChanged.value++;

  /// The user's current name. Set when the profile is edited, so the Home
  /// greeting and avatar update without logging in again.
  static final ValueNotifier<String?> fullName = ValueNotifier<String?>(null);

  /// Asks the app to open the Analysis tab on a given sub-tab
  /// (see AnalysisTabs below).
  static final ValueNotifier<int?> openAnalysisTab = ValueNotifier<int?>(null);

  static void openAnalysis(int tab) {
    openAnalysisTab.value = null; // so tapping the same card twice still works
    openAnalysisTab.value = tab;
  }
}

/// Positions of the tabs on the Analysis screen.
class AnalysisTabs {
  static const insights = 0;
  static const habits = 1;
  static const recurring = 2;
  static const anomalies = 3;
  static const forecast = 4;

  /// Maps the backend's tab names ("anomalies", "forecast"...) to positions.
  static int? fromName(String? name) => const {
        'insights': insights,
        'habits': habits,
        'recurring': recurring,
        'anomalies': anomalies,
        'forecast': forecast,
      }[name];
}