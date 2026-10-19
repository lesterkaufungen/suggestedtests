import '../system_probe.dart';

/// Loads the native bridge, so its startup report (`SUGGESTEDTESTS_VERBOSE=1`)
/// is printed even in runs that never call a native helper.
///
/// Dart runs nothing when a library is imported, so every public entry point
/// of this package calls this first: test files usually call one (`testCases`,
/// `scenario`, ...) while registering their tests, before any test runs. It
/// loads once and never throws: where the bridge is unavailable,
/// [SystemProbe.skipReason] says why.
void preloadNativeBridge() {
  if (!SystemProbe.isAvailable) return;
}
