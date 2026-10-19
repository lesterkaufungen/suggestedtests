import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('import stays under 50 MiB', () async {
    final before = ProcessInfo.maxRss;
    await importer.run(bigFile);
    final growth = ProcessInfo.maxRss - before;
    expect(
      growth,
      lessThanOrEqualTo(50 * 1024 * 1024),
      reason: 'peak RSS grew by ${growth ~/ (1024 * 1024)} MiB > 50 MiB',
    );
  });
}
