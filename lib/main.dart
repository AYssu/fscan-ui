import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:fscan/core/theme/app_theme.dart';
import 'package:fscan/core/theme/theme_provider.dart';
import 'package:fscan/core/theme/background_provider.dart';
import 'package:fscan/core/config/app_config.dart';
import 'package:fscan/core/network/ws_service.dart';
import 'package:fscan/core/utils/logger.dart';
import 'package:fscan/core/services/user_service.dart';
import 'package:fscan/routing/app_router.dart';

/// 应用入口
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化日志系统
  await logger.init();

  final themeProvider = ThemeProvider();
  await themeProvider.init();

  final backgroundProvider = BackgroundProvider();
  await backgroundProvider.init();

  final userService = UserService();
  await userService.init();

  final wsService = WsService();
  await wsService.init();

  final appConfig = AppConfig();
  await appConfig.init();

  logger.info('App', '应用启动完成');

  runApp(MyApp(themeProvider: themeProvider, backgroundProvider: backgroundProvider, userService: userService, wsService: wsService, appConfig: appConfig));
}

/// 应用根组件
class MyApp extends StatelessWidget {
  final ThemeProvider themeProvider;
  final BackgroundProvider backgroundProvider;
  final UserService userService;
  final WsService wsService;
  final AppConfig appConfig;

  const MyApp({super.key, required this.themeProvider, required this.backgroundProvider, required this.userService, required this.wsService, required this.appConfig});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: backgroundProvider),
        ChangeNotifierProvider.value(value: appConfig),
        ChangeNotifierProvider.value(value: wsService),
        ChangeNotifierProvider.value(value: userService),
        ChangeNotifierProvider.value(value: logger),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (context, child) {
          return Consumer2<ThemeProvider, BackgroundProvider>(
            builder: (context, themeProvider, bgProvider, child) {
              final hasBg = bgProvider.hasBackground;
              final cardColor = ColorScheme.fromSeed(
                seedColor: themeProvider.seedColor,
                brightness: themeProvider.isDarkMode ? Brightness.dark : Brightness.light,
              ).surface.withValues(alpha: bgProvider.cardOpacity);

              return MaterialApp.router(
                title: 'FastScan',
                theme: AppTheme.lightTheme(seedColor: themeProvider.seedColor).copyWith(
                  scaffoldBackgroundColor: hasBg ? Colors.transparent : null,
                  cardTheme: AppTheme.lightTheme(seedColor: themeProvider.seedColor).cardTheme.copyWith(
                    color: hasBg ? cardColor : null,
                  ),
                ),
                darkTheme: AppTheme.darkTheme(seedColor: themeProvider.seedColor).copyWith(
                  scaffoldBackgroundColor: hasBg ? Colors.transparent : null,
                  cardTheme: AppTheme.darkTheme(seedColor: themeProvider.seedColor).cardTheme.copyWith(
                    color: hasBg ? cardColor : null,
                  ),
                ),
                themeMode: themeProvider.themeMode,
                routerConfig: appRouter,
                debugShowCheckedModeBanner: false,
                builder: (context, child) {
                  return _AppBackground(child: child ?? const SizedBox());
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// 全局背景组件 - 监听 BackgroundProvider 变化
class _AppBackground extends StatelessWidget {
  final Widget child;
  const _AppBackground({required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<BackgroundProvider>(
      builder: (context, bgProvider, _) {
        return Stack(
          children: [
            // 底层：半透明背景图
            if (bgProvider.hasBackground)
              Positioned.fill(
                child: Opacity(
                  opacity: bgProvider.opacity,
                  child: Image.file(
                    File(bgProvider.imagePath!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            // 上层：正常内容
            child,
          ],
        );
      },
    );
  }
}
