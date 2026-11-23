import 'package:flutter_test/flutter_test.dart';
import 'package:cineflow_flutter/main.dart';

void main() {
  testWidgets('App boots and shows tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const CineFlowApp());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('Universal Downloader'), findsOneWidget);
    expect(find.textContaining('Series'), findsWidgets);
    expect(find.textContaining('Lead Generator'), findsWidgets);
    expect(find.textContaining('Task Scheduler'), findsWidgets);
  });
}
