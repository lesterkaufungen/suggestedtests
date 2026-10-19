import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';

import 'system_probe.dart';
import 'native/preload.dart';

/// Which statistic of a [BenchmarkResult] a performance budget is checked
/// against.
enum Statistic {
  /// Fastest sample.
  min,

  /// Arithmetic mean of all samples.
  mean,

  /// Middle sample. Robust against GC pauses; the default.
  median,

  /// 95th percentile sample.
  p95,

  /// Slowest sample.
  max,
}

/// What a benchmark measures.
enum BenchmarkClock {
  /// Elapsed wall-clock time ([Stopwatch]). Includes time spent waiting and
  /// time stolen by other processes. Works everywhere.
  wall,

  /// CPU time, via the native bridge ([SystemProbe]). Ignores waiting and
  /// other processes, so it is far less noisy on busy CI machines.
  ///
  /// [benchmarkSync] measures the calling thread's CPU time; [benchmark]
  /// measures the whole process' CPU time, because an isolate may switch OS
  /// threads across `await`s.
  cpu,
}

/// Timing statistics collected by [benchmark] or [benchmarkSync].
@immutable
class BenchmarkResult {
  /// Builds a result from raw [samples]. [samples] must not be empty.
  BenchmarkResult(
    this.name,
    List<Duration> samples, {
    this.clock = BenchmarkClock.wall,
  }) : samples = List.unmodifiable(samples),
       _sorted = ([...samples]..sort()) {
    if (samples.isEmpty) {
      throw ArgumentError.value(samples, 'samples', 'must not be empty');
    }
  }

  /// Label of the benchmark.
  final String name;

  /// What the [samples] measure.
  final BenchmarkClock clock;

  /// Measured durations in run order (warm-up runs excluded).
  final List<Duration> samples;

  final List<Duration> _sorted;

  /// Fastest sample.
  Duration get min => _sorted.first;

  /// Slowest sample.
  Duration get max => _sorted.last;

  /// Arithmetic mean.
  Duration get mean => Duration(
    microseconds:
        (samples.fold<int>(0, (s, d) => s + d.inMicroseconds) / samples.length)
            .round(),
  );

  /// Median (50th percentile).
  Duration get median => percentile(50);

  /// 95th percentile.
  Duration get p95 => percentile(95);

  /// Standard deviation of the samples.
  Duration get stdDev {
    final m = mean.inMicroseconds;
    final variance =
        samples.fold<double>(
          0,
          (s, d) => s + math.pow(d.inMicroseconds - m, 2),
        ) /
        samples.length;
    return Duration(microseconds: math.sqrt(variance).round());
  }

  /// The [p]th percentile (0–100) using nearest-rank.
  Duration percentile(num p) {
    if (p < 0 || p > 100) throw RangeError.range(p, 0, 100, 'p');
    final rank = (p / 100 * _sorted.length).ceil().clamp(1, _sorted.length);
    return _sorted[rank - 1];
  }

  /// Returns the value of [statistic].
  Duration operator [](Statistic statistic) => switch (statistic) {
    Statistic.min => min,
    Statistic.mean => mean,
    Statistic.median => median,
    Statistic.p95 => p95,
    Statistic.max => max,
  };

  @override
  String toString() =>
      '$name${clock == BenchmarkClock.cpu ? ' (cpu)' : ''}: '
      'n=${samples.length} '
      'min=${_fmt(min)} median=${_fmt(median)} mean=${_fmt(mean)} '
      'p95=${_fmt(p95)} max=${_fmt(max)} ±${_fmt(stdDev)}';
}

String _fmt(Duration d) {
  final us = d.inMicroseconds;
  if (us < 1000) return '$usµs';
  if (us < 1000000) return '${(us / 1000).toStringAsFixed(2)}ms';
  return '${(us / 1000000).toStringAsFixed(2)}s';
}

void _checkCounts(int iterations, int warmup) {
  if (iterations < 1) throw RangeError.value(iterations, 'iterations');
  if (warmup < 0) throw RangeError.value(warmup, 'warmup');
}

/// Returns a function that reads the current value of [clock].
Duration Function() _reader(BenchmarkClock clock, {required bool sync}) {
  switch (clock) {
    case BenchmarkClock.wall:
      final sw = Stopwatch()..start();
      return () => sw.elapsed;
    case BenchmarkClock.cpu:
      if (!SystemProbe.isAvailable) {
        throw StateError(
          'BenchmarkClock.cpu needs the native bridge: '
          '${SystemProbe.skipReason}',
        );
      }
      return sync
          ? SystemProbe.threadCpuTime
          : () => SystemProbe.processCpuTime().total;
  }
}

/// Runs [body] [warmup] times untimed, then [iterations] times timed, and
/// returns the timing statistics. Awaits [body] if it returns a future.
///
/// Uses a real [Stopwatch], so it measures wall-clock time even inside
/// `testWidgets`' fake-async zone.
Future<BenchmarkResult> benchmark(
  String name,
  FutureOr<void> Function() body, {
  int iterations = 20,
  int warmup = 3,
  BenchmarkClock clock = BenchmarkClock.wall,
}) async {
  preloadNativeBridge();
  _checkCounts(iterations, warmup);
  final now = _reader(clock, sync: false);
  for (var i = 0; i < warmup; i++) {
    await body();
  }
  final samples = <Duration>[];
  for (var i = 0; i < iterations; i++) {
    final start = now();
    await body();
    samples.add(now() - start);
  }
  return BenchmarkResult(name, samples, clock: clock);
}

/// Synchronous variant of [benchmark]. Avoids the microtask hop between
/// iterations, so it is more precise for very fast code.
BenchmarkResult benchmarkSync(
  String name,
  void Function() body, {
  int iterations = 20,
  int warmup = 3,
  BenchmarkClock clock = BenchmarkClock.wall,
}) {
  preloadNativeBridge();
  _checkCounts(iterations, warmup);
  final now = _reader(clock, sync: true);
  for (var i = 0; i < warmup; i++) {
    body();
  }
  final samples = <Duration>[];
  for (var i = 0; i < iterations; i++) {
    final start = now();
    body();
    samples.add(now() - start);
  }
  return BenchmarkResult(name, samples, clock: clock);
}

/// Benchmarks [body] and fails the test if the chosen [statistic] exceeds
/// [budget]. Returns the result so it can be logged or inspected further.
///
/// ```dart
/// test('parsing stays fast', () async {
///   await expectPerformance(
///     () => parse(bigJson),
///     budget: const Duration(milliseconds: 5),
///   );
/// });
/// ```
Future<BenchmarkResult> expectPerformance(
  FutureOr<void> Function() body, {
  required Duration budget,
  Statistic statistic = Statistic.median,
  int iterations = 20,
  int warmup = 3,
  String name = 'benchmark',
  BenchmarkClock clock = BenchmarkClock.wall,
}) async {
  preloadNativeBridge();
  final result = await benchmark(
    name,
    body,
    iterations: iterations,
    warmup: warmup,
    clock: clock,
  );
  final actual = result[statistic];
  if (actual > budget) {
    fail(
      'Performance budget exceeded: ${statistic.name} ${_fmt(actual)} > '
      'budget ${_fmt(budget)}\n$result',
    );
  }
  return result;
}

/// Awaits [future] and fails the test unless it completes successfully within
/// [limit] of wall-clock time. Returns the future's value.
///
/// ```dart
/// final user = await expectCompletesWithin(
///   repository.load(),
///   const Duration(seconds: 1),
/// );
/// ```
///
/// Relies on real timers: use it in `test`, not inside `testWidgets`.
Future<T> expectCompletesWithin<T>(Future<T> future, Duration limit) async {
  preloadNativeBridge();
  try {
    return await future.timeout(limit);
  } on TimeoutException {
    fail('Future did not complete within ${_fmt(limit)}');
  }
}
