import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';

void main() {
  testCases<String, int>('String.length', const [
    TestCase('', 0),
    TestCase('abc', 3),
    TestCase('héllo', 5, name: 'non-ascii'),
  ], (input, expected) {
    expect(input.length, expected);
  });

  testCases<int, int>('async body', const [
    TestCase(1, 2),
    TestCase(5, 10),
  ], (input, expected) async {
    final doubled = await Future.value(input * 2);
    expect(doubled, expected);
  });

  testCases<int, int>('skipped rows', const [
    TestCase(1, 1),
    TestCase(1, 999, skip: 'demonstrates skip'),
  ], (input, expected) {
    expect(input, expected);
  });

  testWidgetsCases<String, Matcher>('greeting', const [
    TestCase('Ada', findsOneWidget),
    TestCase('Linus', findsOneWidget),
  ], (tester, name, matcher) async {
    await tester.pumpApp(Text('Hi $name'));
    expect(find.text('Hi $name'), matcher);
  });

  test('TestCase.label defaults to input -> expected', () {
    expect(const TestCase(1, 2).label, '1 -> 2');
    expect(const TestCase(1, 2, name: 'x').label, 'x');
  });

  test('testCases rejects empty cases', () {
    expect(
      () => testCases<int, int>('empty', const [], (_, __) {}),
      throwsArgumentError,
    );
  });
}
