import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('profile loads', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ProfilePage())),
    );
    final finder = find.text('Ada');
    for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsOneWidget, reason: "'Ada' not shown after 10 s");
  });
}
