import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';

import 'system_probe.dart';

/// Memory before and after running a body with [measureMemory].
@immutable
class MemoryReport {
  /// Creates a report from two samples.
  const MemoryReport(this.before, this.after);

  /// Sample taken before the body ran.
  final MemoryUsage before;

  /// Sample taken after the body completed.
  final MemoryUsage after;

  /// Change in resident memory. Can be negative.
  int get rssGrowthBytes => after.currentRssBytes - before.currentRssBytes;

  /// How far the body pushed the process' peak RSS above its previous peak.
  /// `0` if the body never exceeded the earlier peak.
  int get peakGrowthBytes => after.peakRssBytes - before.peakRssBytes;

  @override
  String toString() => 'MemoryReport(rss: ${_signed(rssGrowthBytes)}, '
      'peak: ${_signed(peakGrowthBytes)}, now: $after)';
}

String _signed(int bytes) => '${bytes >= 0 ? '+' : ''}${formatBytes(bytes)}';

/// Runs [body] and reports how resident memory changed.
///
/// RSS is a coarse, process-wide signal: the Dart GC may hold on to freed
/// memory, and other isolates share the process. Use it to catch leaks and
/// blow-ups of megabytes, not to count individual objects.
Future<MemoryReport> measureMemory(FutureOr<void> Function() body) async {
  final before = SystemProbe.memoryUsage();
  await body();
  return MemoryReport(before, SystemProbe.memoryUsage());
}

/// Runs [body] and fails the test if resident memory grew by more than
/// [maxRssGrowthBytes], or the peak rose by more than [maxPeakGrowthBytes].
/// At least one budget is required.
///
/// ```dart
/// test('loading 10k rows stays under 50 MiB',
///     skip: SystemProbe.skipReason, () async {
///   await expectMemory(
///     () => repository.loadAll(),
///     maxPeakGrowthBytes: 50 * 1024 * 1024,
///   );
/// });
/// ```
Future<MemoryReport> expectMemory(
  FutureOr<void> Function() body, {
  int? maxRssGrowthBytes,
  int? maxPeakGrowthBytes,
}) async {
  if (maxRssGrowthBytes == null && maxPeakGrowthBytes == null) {
    throw ArgumentError('Provide maxRssGrowthBytes and/or maxPeakGrowthBytes.');
  }
  final report = await measureMemory(body);
  if (maxRssGrowthBytes != null && report.rssGrowthBytes > maxRssGrowthBytes) {
    fail(
        'Memory budget exceeded: RSS grew ${formatBytes(report.rssGrowthBytes)}'
        ' > budget ${formatBytes(maxRssGrowthBytes)}\n$report');
  }
  if (maxPeakGrowthBytes != null &&
      report.peakGrowthBytes > maxPeakGrowthBytes) {
    fail('Memory budget exceeded: peak RSS grew '
        '${formatBytes(report.peakGrowthBytes)} > budget '
        '${formatBytes(maxPeakGrowthBytes)}\n$report');
  }
  return report;
}
