import 'package:bar_tab/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BarTabApp shows the German placeholder title', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const BarTabApp());
    await tester.pumpAndSettle();

    expect(find.text('bar-tab'), findsOneWidget);
  });
}
