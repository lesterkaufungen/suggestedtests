import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';

void main() {
  test('import stays under 50 MiB', skip: SystemProbe.skipReason, () async {
    await expectMemory(
      () => importer.run(bigFile),
      maxPeakGrowthBytes: 50 * 1024 * 1024,
    );
  });
}
