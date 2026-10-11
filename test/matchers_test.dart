import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';

void main() {
  test('hasUniqueElements', () {
    expect([1, 2, 3], hasUniqueElements);
    expect(<int>[], hasUniqueElements);
    expect([1, 2, 1], isNot(hasUniqueElements));
    expect('abc', isNot(hasUniqueElements));
  });

  test('hasUniqueElements names the duplicate', () {
    expect(
      () => expect([1, 7, 2, 7], hasUniqueElements),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          contains('contains duplicate <7>'),
        ),
      ),
    );
  });
}
