import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';
import 'native/preload.dart';

/// A single row of a table-driven test: an [input], the [expected] output and
/// an optional human readable [name] used in the test description.
@immutable
class TestCase<I, O> {
  /// Creates a test case.
  const TestCase(this.input, this.expected, {this.name, this.skip});

  /// The value passed to the test body.
  final I input;

  /// The value the test body is expected to produce.
  final O expected;

  /// Optional label. Defaults to `input -> expected`.
  final String? name;

  /// Skip this row. `true` or a reason string, as with `test(skip:)`.
  final Object? skip;

  /// The description used for the generated test.
  String get label => name ?? '$input -> $expected';

  @override
  String toString() => 'TestCase($label)';
}

/// Registers one `test` per entry in [cases], grouped under [description].
///
/// Each row gets its own test, so a failing row is reported by name and does
/// not hide the others.
///
/// ```dart
/// testCases<String, int>('length', const [
///   TestCase('', 0),
///   TestCase('abc', 3),
/// ], (input, expected) {
///   expect(input.length, expected);
/// });
/// ```
@isTestGroup
void testCases<I, O>(
  String description,
  Iterable<TestCase<I, O>> cases,
  FutureOr<void> Function(I input, O expected) body, {
  Timeout? timeout,
  Object? tags,
}) {
  preloadNativeBridge();
  final list = cases.toList(growable: false);
  if (list.isEmpty) {
    throw ArgumentError.value(cases, 'cases', 'must not be empty');
  }
  group(description, () {
    for (final (index, c) in list.indexed) {
      test(
        '[$index] ${c.label}',
        () => body(c.input, c.expected),
        skip: c.skip,
        timeout: timeout,
        tags: tags,
      );
    }
  });
}

/// Like [testCases] but registers one `testWidgets` per row.
///
/// ```dart
/// testWidgetsCases<String, Matcher>('greeting', const [
///   TestCase('Ada', findsOneWidget),
/// ], (tester, name, matcher) async {
///   await tester.pumpApp(Text('Hi $name'));
///   expect(find.text('Hi $name'), matcher);
/// });
/// ```
@isTestGroup
void testWidgetsCases<I, O>(
  String description,
  Iterable<TestCase<I, O>> cases,
  Future<void> Function(WidgetTester tester, I input, O expected) body, {
  Timeout? timeout,
  Object? tags,
}) {
  preloadNativeBridge();
  final list = cases.toList(growable: false);
  if (list.isEmpty) {
    throw ArgumentError.value(cases, 'cases', 'must not be empty');
  }
  group(description, () {
    for (final (index, c) in list.indexed) {
      testWidgets(
        '[$index] ${c.label}',
        (tester) => body(tester, c.input, c.expected),
        skip: c.skip == null || c.skip == false ? null : true,
        timeout: timeout,
        tags: tags,
      );
    }
  });
}
