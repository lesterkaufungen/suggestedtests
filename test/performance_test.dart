import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';

List<Duration> _ms(List<int> values) =>
    [for (final v in values) Duration(milliseconds: v)];

void main() {
  group('BenchmarkResult', () {
    final result = BenchmarkResult('r', _ms([5, 1, 3, 2, 4]));

    test('statistics', () {
      expect(result.min, const Duration(milliseconds: 1));
      expect(result.max, const Duration(milliseconds: 5));
      expect(result.mean, const Duration(milliseconds: 3));
      expect(result.median, const Duration(milliseconds: 3));
      expect(result.p95, const Duration(milliseconds: 5));
      expect(result[Statistic.min], result.min);
    });

    test('keeps samples in run order', () {
      expect(result.samples, _ms([5, 1, 3, 2, 4]));
    });

    test('stdDev', () {
      // population stddev of 1..5 ms = sqrt(2) ms
      expect(result.stdDev.inMicroseconds, closeTo(1414, 1));
    });

    test('rejects empty samples and bad percentiles', () {
      expect(() => BenchmarkResult('e', const []), throwsArgumentError);
      expect(() => result.percentile(101), throwsRangeError);
    });

    test('toString is readable', () {
      expect(result.toString(), contains('median=3.00ms'));
    });
  });

  test('benchmarkSync runs warmup + iterations', () {
    var runs = 0;
    final r = benchmarkSync('count', () => runs++, iterations: 7, warmup: 2);
    expect(runs, 9);
    expect(r.samples, hasLength(7));
  });

  test('benchmark awaits async bodies', () async {
    var runs = 0;
    final r = await benchmark('async', () async {
      await Future<void>.delayed(Duration.zero);
      runs++;
    }, iterations: 3, warmup: 1);
    expect(runs, 4);
    expect(r.samples, hasLength(3));
  });

  test('benchmark validates counts', () {
    expect(() => benchmarkSync('x', () {}, iterations: 0), throwsRangeError);
    expect(() => benchmarkSync('x', () {}, warmup: -1), throwsRangeError);
  });

  test('expectPerformance passes within budget', () async {
    final r = await expectPerformance(
      () {},
      budget: const Duration(seconds: 1),
    );
    expect(r.samples, hasLength(20));
  });

  test('expectPerformance fails over budget', () async {
    await expectLater(
      expectPerformance(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
        budget: const Duration(milliseconds: 1),
        iterations: 2,
        warmup: 0,
      ),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          contains('Performance budget exceeded'),
        ),
      ),
    );
  });

  group('expectCompletesWithin', () {
    test('returns the value of a fast future', () async {
      expect(
        await expectCompletesWithin(
            Future.value(1), const Duration(seconds: 1)),
        1,
      );
    });

    test('fails on a slow future', () async {
      await expectLater(
        expectCompletesWithin(
          Future<void>.delayed(const Duration(milliseconds: 200)),
          const Duration(milliseconds: 10),
        ),
        throwsA(
          isA<TestFailure>().having(
            (e) => e.message,
            'message',
            contains('did not complete within 10.00ms'),
          ),
        ),
      );
    });

    test('propagates errors', () async {
      await expectLater(
        expectCompletesWithin(
          Future<void>.error(StateError('x')),
          const Duration(seconds: 1),
        ),
        throwsStateError,
      );
    });
  });

  group('BenchmarkClock.cpu', skip: SystemProbe.skipReason, () {
    test('benchmarkSync measures thread CPU time', () {
      final r = benchmarkSync(
        'busy',
        () {
          var x = 0;
          for (var i = 0; i < 2000000; i++) {
            x ^= i;
          }
          expect(x, isNonNegative);
        },
        iterations: 5,
        clock: BenchmarkClock.cpu,
      );
      expect(r.clock, BenchmarkClock.cpu);
      expect(r.toString(), startsWith('busy (cpu): '));
    });

    test('cpu clock ignores time spent waiting', () async {
      final r = await benchmark(
        'sleep',
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
        iterations: 3,
        warmup: 0,
        clock: BenchmarkClock.cpu,
      );
      // 30ms of wall time per sample, but almost no CPU.
      expect(r.median, lessThan(const Duration(milliseconds: 20)));
    });
  });
}
