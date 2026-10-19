import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';

const _mib = 1024 * 1024;

// Allocations are kept alive for the whole file so that a later test cannot
// reuse memory an earlier one freed (which would hide RSS growth).
final _retained = <Uint8List>[];

void _allocate(int bytes) =>
    _retained.add(Uint8List(bytes)..fillRange(0, bytes, 1)); // touch pages

void main() {
  tearDownAll(_retained.clear);

  group('memory', skip: SystemProbe.skipReason, () {
    test('measureMemory sees a large allocation', () async {
      final report = await measureMemory(() => _allocate(64 * _mib));
      expect(report.rssGrowthBytes, greaterThan(32 * _mib));
      expect(report.toString(), contains('MemoryReport(rss: +'));
    });

    test('expectMemory passes within budget', () async {
      await expectMemory(() {}, maxRssGrowthBytes: 16 * _mib);
    });

    test('expectMemory fails over budget', () async {
      await expectLater(
        expectMemory(() => _allocate(64 * _mib), maxRssGrowthBytes: _mib),
        throwsA(
          isA<TestFailure>().having(
            (e) => e.message,
            'message',
            contains('Memory budget exceeded: RSS grew'),
          ),
        ),
      );
    });
  });

  test('expectMemory requires a budget', () {
    expect(() => expectMemory(() {}), throwsArgumentError);
  });
}
