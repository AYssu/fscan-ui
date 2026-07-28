import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fscan/core/theme/theme_provider.dart';
import 'package:fscan/core/theme/background_provider.dart';
import 'package:fscan/core/config/app_config.dart';
import 'package:fscan/core/network/ws_service.dart';
import 'package:fscan/core/services/user_service.dart';
import 'package:fscan/main.dart';

void main() {
  testWidgets('App should build without errors', (WidgetTester tester) async {
    // Create and initialize providers
    final themeProvider = ThemeProvider();
    final backgroundProvider = BackgroundProvider();
    final appConfig = AppConfig();
    final wsService = WsService();
    final userService = UserService();

    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp(
      themeProvider: themeProvider,
      backgroundProvider: backgroundProvider,
      appConfig: appConfig,
      wsService: wsService,
      userService: userService,
    ));

    // Verify that the app renders
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
