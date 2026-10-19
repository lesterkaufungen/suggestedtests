import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';

void main() {
  test('parsing stays fast', () async {
    await expectPerformance(
      () => parse(bigJson),
      budget: const Duration(milliseconds: 5),
    );
  });
}
