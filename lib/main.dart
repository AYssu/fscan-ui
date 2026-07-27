import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:fscan/core/theme/app_theme.dart';
import 'package:fscan/core/theme/theme_provider.dart';
import 'package:fscan/core/config/app_config.dart';
import 'package:fscan/routing/app_router.dart';

/// 应用入口
void main() {
  runApp(const MyApp());
}

/// 应用根组件
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AppConfig()),
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
                theme: AppTheme.lightTheme(),
                darkTheme: AppTheme.darkTheme(),
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
