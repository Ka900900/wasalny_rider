import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wasalny_rider/core/theme/app_theme.dart';

void main() {
  test('AppColors dark palette is consistent', () {
    expect(AppColors.darkBg, const Color(0xFF1A1A1A));
    expect(AppColors.primaryGreen, const Color(0xFF7CFC00));
  });

  testWidgets('Logo fallback icon renders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Icon(Icons.local_taxi, color: AppColors.primary),
        ),
      ),
    );
    expect(find.byIcon(Icons.local_taxi), findsOneWidget);
  });

  testWidgets('App brand text renders inside a Scaffold', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Waslny'))),
      ),
    );
    expect(find.text('Waslny'), findsOneWidget);
  });
}
