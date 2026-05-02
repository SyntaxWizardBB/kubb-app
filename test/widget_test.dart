import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/app/app.dart';

void main() {
  testWidgets('App boots and renders the placeholder home', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KubbApp()));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });
}
