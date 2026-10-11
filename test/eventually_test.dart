import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';

void main() {
  test('returns as soon as the body succeeds', () async {
    var attempts = 0;
    final value = await eventually(() {
      attempts++;
      expect(attempts, greaterThanOrEqualTo(3));
      return 'ok';
    }, interval: const Duration(milliseconds: 1));
    expect(value, 'ok');
    expect(attempts, 3);
  });

  test('waits for async state', () async {
    var ready = false;
    Future<void>.delayed(const Duration(milliseconds: 30), () => ready = true);
    await eventually(() => expect(ready, isTrue));
  });

  test('fails with the last error after the timeout', () async {
    await expectLater(
      eventually(
        () => expect(1, 2),
        timeout: const Duration(milliseconds: 50),
        interval: const Duration(milliseconds: 5),
      ),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          allOf(contains('Condition not met'), contains('Expected: <2>')),
        ),
      ),
    );
  });
}
