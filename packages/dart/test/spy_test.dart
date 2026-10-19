import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';

void main() {
  test('records calls and delegates', () {
    final add = Spy2<int, int, int>((a, b) => a + b);
    expect(add(1, 2), 3);
    expect(add(3, 4), 7);
    expect(add.callCount, 2);
    expect(add.calls, [
      [1, 2],
      [3, 4],
    ]);
    expect(add.lastCall, [3, 4]);
  });

  test('matchers', () {
    final onChanged = Spy1<String, void>((_) {});
    expect(onChanged, wasNotCalled);
    onChanged('a');
    onChanged('b');
    expect(onChanged, wasCalled);
    expect(onChanged, wasCalledTimes(2));
    expect(onChanged, wasCalledWith(['b']));
    expect(onChanged, wasCalledWith([startsWith('a')]));
    expect(onChanged, isNot(wasCalledWith(['c'])));
  });

  test('mismatch description lists the calls', () {
    final spy = Spy1<int, void>((_) {});
    spy(1);
    expect(
      () => expect(spy, wasCalledTimes(2)),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          contains('was called 1 time(s)'),
        ),
      ),
    );
  });

  test('reset clears calls', () {
    final spy = Spy0<int>(() => 1)..call();
    spy.reset();
    expect(spy, wasNotCalled);
    expect(() => spy.lastCall, throwsStateError);
  });

  testWidgets('works as a widget callback', (tester) async {
    final onPressed = Spy0<void>(() {});
    await tester.pumpApp(
      ElevatedButton(onPressed: onPressed.call, child: const Text('tap')),
    );
    await tester.tapAndSettle(find.text('tap'));
    expect(onPressed, wasCalledTimes(1));
  });
}
