import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';

void main() {
  testWidgets('profile loads', (tester) async {
    await tester.pumpApp(const ProfilePage());
    await tester.pumpUntilFound(find.text('Ada'));
  });
}
