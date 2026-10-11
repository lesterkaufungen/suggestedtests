import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suggestedtests/suggestedtests.dart';

class _Delayed extends StatefulWidget {
  const _Delayed();

  @override
  State<_Delayed> createState() => _DelayedState();
}

class _DelayedState extends State<_Delayed> {
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) => loaded
      ? const Text('done')
      // Endless animation: pumpAndSettle would time out here.
      : const CircularProgressIndicator();
}

void main() {
  testWidgets('pumpApp provides Material ancestors', (tester) async {
    await tester.pumpApp(Builder(
      builder: (context) => Text(Theme.of(context).brightness.name),
    ));
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('light'), findsOneWidget);
  });

  testWidgets('pumpApp without scaffold', (tester) async {
    await tester.pumpApp(const Text('x'), wrapInScaffold: false);
    expect(find.byType(Scaffold), findsNothing);
  });

  testWidgets('pumpApp sets the surface size', (tester) async {
    await tester.pumpApp(
      Builder(
        builder: (context) => Text('${MediaQuery.sizeOf(context).width}'),
      ),
      surfaceSize: const Size(320, 640),
    );
    expect(find.text('320.0'), findsOneWidget);
  });

  testWidgets('enterTextAndSettle', (tester) async {
    final onChanged = Spy1<String, void>((_) {});
    await tester.pumpApp(TextField(onChanged: onChanged.call));
    await tester.enterTextAndSettle(find.byType(TextField), 'hello');
    expect(onChanged, wasCalledWith(['hello']));
  });

  testWidgets('pumpUntilFound / pumpUntilGone with endless animation',
      (tester) async {
    await tester.pumpApp(const _Delayed());
    await tester.pumpUntilFound(find.text('done'));
    await tester.pumpUntilGone(find.byType(CircularProgressIndicator));
    expect(find.text('done'), findsOneWidget);
  });

  testWidgets('pumpUntilFound times out', (tester) async {
    await tester.pumpApp(const SizedBox());
    Object? error;
    try {
      await tester.pumpUntilFound(
        find.text('never'),
        timeout: const Duration(milliseconds: 300),
      );
    } on TestFailure catch (e) {
      error = e;
    }
    expect(
      error,
      isA<TestFailure>().having(
        (e) => e.message,
        'message',
        contains('Timed out after 0:00:00.300000'),
      ),
    );
  });
}
