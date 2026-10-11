import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Re-runs [body] every [interval] until it completes without throwing, then
/// returns its result. If it still throws after [timeout], the test fails with
/// the last error.
///
/// Replaces fixed `Future.delayed` sleeps: the test continues as soon as the
/// condition holds instead of always waiting for the worst case.
///
/// ```dart
/// await eventually(() => expect(cache.isWarm, isTrue));
/// ```
///
/// Relies on real timers: use it in `test`. Inside `testWidgets`, use
/// `tester.pumpUntilFound` instead.
Future<T> eventually<T>(
  FutureOr<T> Function() body, {
  Duration timeout = const Duration(seconds: 5),
  Duration interval = const Duration(milliseconds: 20),
}) async {
  final sw = Stopwatch()..start();
  var attempts = 0;
  while (true) {
    attempts++;
    try {
      return await body();
    } catch (error, stack) {
      if (sw.elapsed >= timeout) {
        Error.throwWithStackTrace(
          TestFailure('Condition not met within $timeout '
              '($attempts attempts). Last error:\n$error'),
          stack,
        );
      }
    }
    await Future<void>.delayed(interval);
  }
}
