// This is a basic Flutter widget test.

import 'package:flutter_test/flutter_test.dart';
import 'package:abrova_sync_example/main.dart';

void main() {
  testWidgets('App builds correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const AbrovaSyncExampleApp());

    // Verify that the app builds
    expect(find.text('AbrovaSync Demo'), findsOneWidget);
  });
}
