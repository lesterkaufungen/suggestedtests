import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shortcuts for common `WidgetTester` sequences.
extension SuggestedWidgetTester on WidgetTester {
  /// Pumps [widget] inside a `MaterialApp` + `Scaffold`, so widgets that need
  /// `Theme`, `MediaQuery`, `Directionality` or a `Navigator` just work.
  ///
  /// Set [surfaceSize] (logical pixels) to test a specific screen size; it is
  /// reset automatically when the test ends. Set [wrapInScaffold] to `false`
  /// when [widget] is itself a full screen.
  Future<void> pumpApp(
    Widget widget, {
    ThemeData? theme,
    Locale? locale,
    Size? surfaceSize,
    bool wrapInScaffold = true,
    List<NavigatorObserver> navigatorObservers = const [],
  }) async {
    if (surfaceSize != null) {
      view.physicalSize = surfaceSize * view.devicePixelRatio;
      addTearDown(view.reset);
    }
    await pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        locale: locale,
        navigatorObservers: navigatorObservers,
        home: wrapInScaffold ? Scaffold(body: widget) : widget,
      ),
    );
  }

  /// Taps [finder] and waits for all animations to settle.
  Future<void> tapAndSettle(Finder finder) async {
    await tap(finder);
    await pumpAndSettle();
  }

  /// Enters [text] into [finder] and waits for all animations to settle.
  Future<void> enterTextAndSettle(Finder finder, String text) async {
    await enterText(finder, text);
    await pumpAndSettle();
  }

  /// Pumps frames every [step] until [finder] finds at least one widget.
  ///
  /// Unlike `pumpAndSettle`, this works with endless animations such as
  /// progress indicators. Fails the test after [timeout] (fake time).
  Future<void> pumpUntilFound(
    Finder finder, {
    Duration timeout = const Duration(seconds: 10),
    Duration step = const Duration(milliseconds: 100),
  }) =>
      _pumpUntil(
          () => finder.evaluate().isNotEmpty, 'find $finder', timeout, step);

  /// Pumps frames every [step] until [finder] finds nothing.
  Future<void> pumpUntilGone(
    Finder finder, {
    Duration timeout = const Duration(seconds: 10),
    Duration step = const Duration(milliseconds: 100),
  }) =>
      _pumpUntil(() => finder.evaluate().isEmpty, '$finder to disappear',
          timeout, step);

  Future<void> _pumpUntil(
    bool Function() condition,
    String what,
    Duration timeout,
    Duration step,
  ) async {
    var elapsed = Duration.zero;
    while (!condition()) {
      if (elapsed >= timeout) {
        fail('Timed out after $timeout waiting for $what');
      }
      await pump(step);
      elapsed += step;
    }
  }
}
