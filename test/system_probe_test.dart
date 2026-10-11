import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';

int _burn() {
  var x = 0;
  for (var i = 0; i < 30000000; i++) {
    x = (x * 31 + i) & 0xffffffff;
  }
  return x;
}

void main() {
  // The bridge must load wherever this package's own tests run (dev machines
  // and CI all have either a prebuilt library or cargo).
  test('native bridge is available', () {
    expect(SystemProbe.isAvailable, isTrue, reason: SystemProbe.skipReason);
    expect(SystemProbe.skipReason, isNull);
  });

  group('SystemProbe', skip: SystemProbe.skipReason, () {
    test('processCpuTime grows with work', () {
      final before = SystemProbe.processCpuTime();
      _burn();
      final spent = SystemProbe.processCpuTime() - before;
      expect(spent.total, greaterThan(Duration.zero));
      expect(spent.user, greaterThanOrEqualTo(Duration.zero));
      expect(spent.system, greaterThanOrEqualTo(Duration.zero));
    });

    test('threadCpuTime grows with work', () {
      final before = SystemProbe.threadCpuTime();
      _burn();
      expect(SystemProbe.threadCpuTime(), greaterThan(before));
    });

    test('memoryUsage is plausible', () {
      final m = SystemProbe.memoryUsage();
      expect(m.currentRssBytes, greaterThan(1024 * 1024));
      expect(m.peakRssBytes, greaterThanOrEqualTo(m.currentRssBytes));
    });

    test('cpuCount matches dart:io', () {
      expect(SystemProbe.cpuCount, greaterThanOrEqualTo(1));
      expect(
          SystemProbe.cpuCount, lessThanOrEqualTo(Platform.numberOfProcessors));
    });
  });

  test('CpuTime arithmetic and equality', () {
    const a = CpuTime(user: Duration(seconds: 3), system: Duration(seconds: 1));
    const b = CpuTime(user: Duration(seconds: 1), system: Duration(seconds: 1));
    expect(a - b,
        const CpuTime(user: Duration(seconds: 2), system: Duration.zero));
    expect(a.total, const Duration(seconds: 4));
  });

  test('NativeBridgeException describes the error', () {
    expect(NativeBridgeException('memoryUsage', 2).toString(),
        contains('memoryUsage failed: OS error 2'));
    expect(NativeBridgeException('x', -2).toString(),
        contains('not supported on this OS'));
  });

  test('formatBytes', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1023), '1023 B');
    expect(formatBytes(1536), '1.5 KiB');
    expect(formatBytes(-5 * 1024 * 1024), '-5.0 MiB');
    expect(formatBytes(-12), '-12 B');
  });
}
