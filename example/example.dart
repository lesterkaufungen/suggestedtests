// Run with: flutter test example/example.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';

int fib(int n) => n < 2 ? n : fib(n - 1) + fib(n - 2);

class Counter extends StatefulWidget {
  const Counter({super.key, this.onChanged});

  final ValueChanged<int>? onChanged;

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int value = 0;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text('$value'),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              setState(() => value++);
              widget.onChanged?.call(value);
            },
          ),
        ],
      );
}

void main() {
  // One test per row; failing rows are reported by name.
  testCases<int, int>(
      'fib',
      const [
        TestCase(0, 0),
        TestCase(1, 1),
        TestCase(10, 55),
      ],
      (n, expected) => expect(fib(n), expected));

  // Given / when / then, with the failing step named in the report.
  scenarioWidgets('tapping + increments the counter', (tester, s) {
    final onChanged = Spy1<int, void>((_) {});
    s.given(
        'a counter', () => tester.pumpApp(Counter(onChanged: onChanged.call)));
    s.when('+ is tapped twice', () async {
      await tester.tapAndSettle(find.byIcon(Icons.add));
      await tester.tapAndSettle(find.byIcon(Icons.add));
    });
    s.then('it shows 2', () => expect(find.text('2'), findsOneWidget));
    s.and('onChanged saw 1 then 2', () {
      expect(onChanged.calls, [
        [1],
        [2],
      ]);
    });
  });

  // Fail the build when code gets slower than its budget.
  test('fib(20) stays under 50ms', () async {
    final result = await expectPerformance(
      () => fib(20),
      budget: const Duration(milliseconds: 50),
      name: 'fib(20)',
    );
    debugPrint(result.toString());
  });

  // Reproducible fake data.
  test('sorting users by age', () {
    final data = TestData(42);
    final ages = data.listOf(50, (d) => d.integer(18, 90))..sort();
    expect(ages, isSorted<num>());
  });

  // Wait for a condition instead of sleeping a fixed time.
  test('eventually', () async {
    var ready = false;
    Future<void>.delayed(const Duration(milliseconds: 50), () => ready = true);
    await eventually(() => expect(ready, isTrue));
  });
}
