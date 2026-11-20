import 'package:flutter_test/flutter_test.dart';

import 'package:cineflow_flutter/main.dart';

void main() {
  testWidgets('App boots and shows tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const CineFlowApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('CineFlow Studio'), findsWidgets);
    expect(find.textContaining('1. Universal Downloader'), findsOneWidget);
    expect(find.textContaining('2. Series & Drama Watcher'), findsOneWidget);
    expect(find.textContaining('3. Lead Generator & Media Scraper'), findsOneWidget);
    expect(find.textContaining('4. Task Scheduler'), findsOneWidget);
  });
}
