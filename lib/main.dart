import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:fscan/core/theme/app_theme.dart';
import 'package:fscan/core/theme/theme_provider.dart';
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

  final userService = UserService();
  await userService.init();

  logger.info('App', '应用启动完成');

  runApp(MyApp(themeProvider: themeProvider, userService: userService));
}

/// 应用根组件
class MyApp extends StatelessWidget {
  final ThemeProvider themeProvider;
  final UserService userService;

  const MyApp({super.key, required this.themeProvider, required this.userService});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => AppConfig()),
        ChangeNotifierProvider(create: (_) => WsService()),
        ChangeNotifierProvider.value(value: userService),
        ChangeNotifierProvider.value(value: logger),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (context, child) {
          return Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return MaterialApp.router(
                title: 'FScan',
                theme: AppTheme.lightTheme(seedColor: themeProvider.seedColor),
                darkTheme: AppTheme.darkTheme(seedColor: themeProvider.seedColor),
                themeMode: themeProvider.themeMode,
                routerConfig: appRouter,
                debugShowCheckedModeBanner: false,
              );
            },
          );
        },
      ),
    );
  }
}
