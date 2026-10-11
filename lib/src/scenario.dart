import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';

/// Builder passed to a [scenario] body for declaring given/when/then steps.
///
/// Steps run in the order they are declared. When a step fails, the error is
/// rethrown wrapped in a [ScenarioStepFailure] that names the failing step,
/// so reports read like `Then: total is 30 → Expected: 30 Actual: 20`.
class Steps {
  /// Creates an empty step list. Usually you get one from [scenario] or
  /// [scenarioWidgets]; construct it directly to build your own wrappers.
  Steps();

  final List<(String, String, FutureOr<void> Function())> _steps = [];

  /// Declares setup / preconditions.
  void given(String description, FutureOr<void> Function() body) =>
      _steps.add(('Given', description, body));

  /// Declares the action under test.
  void when(String description, FutureOr<void> Function() body) =>
      _steps.add(('When', description, body));

  /// Declares an expectation.
  void then(String description, FutureOr<void> Function() body) =>
      _steps.add(('Then', description, body));

  /// Continues the previous step kind (e.g. a second `then`).
  void and(String description, FutureOr<void> Function() body) =>
      _steps.add(('And', description, body));

  /// Runs the declared steps in order.
  Future<void> run() async {
    if (_steps.isEmpty) {
      throw StateError('scenario declared no steps');
    }
    for (final (keyword, description, body) in _steps) {
      try {
        await body();
      } catch (error, stack) {
        Error.throwWithStackTrace(
          ScenarioStepFailure(keyword, description, error),
          stack,
        );
      }
    }
  }
}

/// Thrown when a [scenario] step fails. Wraps the original [error].
class ScenarioStepFailure implements Exception {
  /// Creates a failure for the step `keyword: description`.
  ScenarioStepFailure(this.keyword, this.description, this.error);

  /// `Given`, `When`, `Then` or `And`.
  final String keyword;

  /// The step description.
  final String description;

  /// The original error thrown by the step.
  final Object error;

  @override
  String toString() => '$keyword: $description\n$error';
}

/// Registers a test whose body is written as given/when/then steps.
///
/// ```dart
/// scenario('adding items updates the total', (s) {
///   late Cart cart;
///   s.given('an empty cart', () => cart = Cart());
///   s.when('two items are added', () => cart..add(10)..add(20));
///   s.then('the total is 30', () => expect(cart.total, 30));
/// });
/// ```
@isTest
void scenario(
  String description,
  void Function(Steps s) declare, {
  Object? skip,
  Timeout? timeout,
  Object? tags,
}) {
  test(
    description,
    () {
      final steps = Steps();
      declare(steps);
      return steps.run();
    },
    skip: skip,
    timeout: timeout,
    tags: tags,
  );
}

/// Like [scenario] but registers a `testWidgets`; the [WidgetTester] is passed
/// to [declare] so steps can pump and interact with widgets.
///
/// ```dart
/// scenarioWidgets('tapping increments the counter', (tester, s) {
///   s.given('the counter page', () => tester.pumpApp(const CounterPage()));
///   s.when('+ is tapped', () => tester.tapAndSettle(find.byIcon(Icons.add)));
///   s.then('it shows 1', () => expect(find.text('1'), findsOneWidget));
/// });
/// ```
@isTest
void scenarioWidgets(
  String description,
  void Function(WidgetTester tester, Steps s) declare, {
  bool? skip,
  Timeout? timeout,
  Object? tags,
}) {
  testWidgets(
    description,
    (tester) {
      final steps = Steps();
      declare(tester, steps);
      return steps.run();
    },
    skip: skip,
    timeout: timeout,
    tags: tags,
  );
}
