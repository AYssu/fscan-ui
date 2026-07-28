import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fscan/core/theme/theme_provider.dart';
import 'package:fscan/core/services/user_service.dart';
import 'package:fscan/main.dart';

void main() {
  testWidgets('App should build without errors', (WidgetTester tester) async {
    // Create and initialize ThemeProvider
    final themeProvider = ThemeProvider();
    final userService = UserService();

    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp(themeProvider: themeProvider, userService: userService));

    // Verify that the app renders
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
