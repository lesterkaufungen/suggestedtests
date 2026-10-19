// tool/release_build.sh runs this with SUGGESTEDTESTS_VERBOSE=1 and checks the
// native bridge printed its startup report: registering tests with this
// package's helpers loads the bridge (lib/src/native/preload.dart), even when
// no native helper is called.
import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';

void main() {
  testCases<int, int>('doubling', const [TestCase(2, 4)], (input, expected) {
    expect(input * 2, expected);
  });
}
