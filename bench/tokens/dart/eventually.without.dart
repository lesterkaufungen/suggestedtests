import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cache warms up', () async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      try {
        expect(cache.isWarm, isTrue);
        return;
      } on TestFailure {
        if (DateTime.now().isAfter(deadline)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  });
}
