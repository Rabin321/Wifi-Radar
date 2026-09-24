import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wifiradar/app.dart';

void main() {
  testWidgets('Wi‑Fi radar home screen loads', (WidgetTester tester) async {
    await tester.pumpWidget(const WifiRadarApp());

    expect(find.text('Wi‑Fi Radar'), findsOneWidget);
    expect(find.text('Scan room'), findsOneWidget);
  });
}
