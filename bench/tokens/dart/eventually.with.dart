import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';

void main() {
  test('cache warms up', () async {
    await eventually(() => expect(cache.isWarm, isTrue));
  });
}
