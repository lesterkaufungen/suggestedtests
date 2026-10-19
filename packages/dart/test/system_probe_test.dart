import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';

/// Spins until [read] returns a larger value and returns both samples.
/// CPU clocks tick coarsely on some systems (~15.6ms on Windows), so a fixed
/// amount of work may not register.
(T, T) _burnUntilAdvances<T extends Comparable<Object>>(T Function() read) {
  final before = read();
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  var x = 0;
  while (true) {
    for (var i = 0; i < 100000; i++) {
      x = (x * 31 + i) & 0xffffffff;
    }
    final after = read();
    if (after.compareTo(before) > 0) return (before, after);
    if (DateTime.now().isAfter(deadline)) fail('CPU clock never advanced ($x)');
  }
}

void main() {
  // The bridge must load wherever this package's own tests run (the release
  // build hides cargo, so this needs the prebuilt library).
  test('native bridge is available', () {
    expect(SystemProbe.isAvailable, isTrue, reason: SystemProbe.skipReason);
    expect(SystemProbe.skipReason, isNull);
  });

  group('SystemProbe', skip: SystemProbe.skipReason, () {
    test('processCpuTime grows with work', () {
      final before = SystemProbe.processCpuTime();
      _burnUntilAdvances(() => SystemProbe.processCpuTime().total);
      final spent = SystemProbe.processCpuTime() - before;
      expect(spent.total, greaterThan(Duration.zero));
      expect(spent.user, greaterThanOrEqualTo(Duration.zero));
      expect(spent.system, greaterThanOrEqualTo(Duration.zero));
    });

    test('threadCpuTime grows with work', () {
      final (before, after) = _burnUntilAdvances(SystemProbe.threadCpuTime);
      expect(after, greaterThan(before));
    });

    test('memoryUsage is plausible', () {
      final m = SystemProbe.memoryUsage();
      expect(m.currentRssBytes, greaterThan(1024 * 1024));
      expect(m.peakRssBytes, greaterThanOrEqualTo(m.currentRssBytes));
    });

    test('cpuCount matches dart:io', () {
      expect(SystemProbe.cpuCount, greaterThanOrEqualTo(1));
      expect(
        SystemProbe.cpuCount,
        lessThanOrEqualTo(Platform.numberOfProcessors),
      );
    });

    test('verbose follows SUGGESTEDTESTS_VERBOSE and round-trips', () {
      final fromEnv = const {'1', 'true', 'yes', 'on'}.contains(
        Platform.environment['SUGGESTEDTESTS_VERBOSE']?.trim().toLowerCase(),
      );
      expect(SystemProbe.verbose, fromEnv);
      // Setting the current value again prints nothing new.
      expect(SystemProbe.setVerbose(fromEnv), fromEnv);
      expect(SystemProbe.verbose, fromEnv);
    });
  });

  test('CpuTime arithmetic and equality', () {
    const a = CpuTime(user: Duration(seconds: 3), system: Duration(seconds: 1));
    const b = CpuTime(user: Duration(seconds: 1), system: Duration(seconds: 1));
    expect(
      a - b,
      const CpuTime(user: Duration(seconds: 2), system: Duration.zero),
    );
    expect(a.total, const Duration(seconds: 4));
  });

  test('NativeBridgeException describes the error', () {
    expect(
      NativeBridgeException('memoryUsage', 2).toString(),
      contains('memoryUsage failed: OS error 2'),
    );
    expect(
      NativeBridgeException('x', -2).toString(),
      contains('not supported on this OS'),
    );
  });

  test('formatBytes', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1023), '1023 B');
    expect(formatBytes(1536), '1.5 KiB');
    expect(formatBytes(-5 * 1024 * 1024), '-5.0 MiB');
    expect(formatBytes(-12), '-12 B');
  });
}
