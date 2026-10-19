import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parsing stays fast', () {
    for (var i = 0; i < 3; i++) {
      parse(bigJson);
    }
    final samples = <int>[];
    final watch = Stopwatch();
    for (var i = 0; i < 20; i++) {
      watch
        ..reset()
        ..start();
      parse(bigJson);
      watch.stop();
      samples.add(watch.elapsedMicroseconds);
    }
    samples.sort();
    final median = (samples[9] + samples[10]) / 2;
    expect(
      median,
      lessThanOrEqualTo(5000),
      reason:
          'parse: median ${median / 1000}ms > budget 5ms '
          '(min ${samples.first / 1000}ms, max ${samples.last / 1000}ms)',
    );
  });
}
