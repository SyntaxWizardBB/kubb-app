import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/main.dart';

void main() {
  testWidgets('App boots and renders the placeholder home', (tester) async {
    await tester.pumpWidget(const KubbApp());
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });
}
