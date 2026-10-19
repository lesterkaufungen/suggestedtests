import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';

class _Cart {
  final items = <int>[];
  int get total => items.fold(0, (a, b) => a + b);
}

void main() {
  scenario('adding items updates the total', (s) {
    late _Cart cart;
    s.given('an empty cart', () => cart = _Cart());
    s.when(
      'two items are added',
      () => cart.items
        ..add(10)
        ..add(20),
    );
    s.then('the total is 30', () => expect(cart.total, 30));
    s.and('it has two items', () => expect(cart.items, hasLength(2)));
  });

  scenarioWidgets('tapping a button shows a label', (tester, s) {
    s.given('a button', () async {
      await tester.pumpApp(
        StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              ElevatedButton(
                onPressed: () => setState(() {}),
                child: const Text('go'),
              ),
              const Text('ready'),
            ],
          ),
        ),
      );
    });
    s.when('it is tapped', () => tester.tapAndSettle(find.text('go')));
    s.then('the label is visible', () {
      expect(find.text('ready'), findsOneWidget);
    });
  });

  test('a failing step is reported by name', () async {
    final steps = Steps()
      ..given('a value', () {})
      ..then('it is wrong', () => expect(1, 2));
    await expectLater(
      steps.run(),
      throwsA(
        isA<ScenarioStepFailure>()
            .having((f) => f.keyword, 'keyword', 'Then')
            .having((f) => f.description, 'description', 'it is wrong')
            .having((f) => f.error, 'error', isA<TestFailure>()),
      ),
    );
  });

  test('steps after a failure do not run', () async {
    var ran = false;
    final steps = Steps()
      ..when('it throws', () => throw StateError('boom'))
      ..then('never', () => ran = true);
    await expectLater(steps.run(), throwsA(isA<ScenarioStepFailure>()));
    expect(ran, isFalse);
  });

  test('an empty scenario is an error', () {
    expect(Steps().run(), throwsStateError);
  });
}
