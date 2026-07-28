 import 'package:go_router/go_router.dart';
import 'package:fscan/features/scan/presentation/screens/scan_screen.dart';
import 'package:fscan/features/compare/presentation/screens/compare_screen.dart';
import 'package:fscan/features/filter/presentation/screens/filter_screen.dart';
import 'package:fscan/features/driver/presentation/screens/driver_screen.dart';
import 'package:fscan/features/config/presentation/screens/config_screen.dart';
import 'package:fscan/features/home/presentation/screens/home_screen.dart';
import 'package:fscan/features/format/presentation/screens/format_screen.dart';
import 'package:fscan/features/pointer_debug/presentation/screens/pointer_debug_screen.dart';

/// 应用路由配置
final appRouter = GoRouter(
  initialLocation: '/scan',
  routes: [
    // 主页面（底部导航栏）
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return HomeScreen(navigationShell: navigationShell);
      },
      branches: [
        // 扫描模块
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/scan',
              builder: (context, state) => const ScanScreen(),
            ),
          ],
        ),
        // 对比模块
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/compare',
              builder: (context, state) => const CompareScreen(),
            ),
          ],
        ),
        // 过滤模块
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/filter',
              builder: (context, state) => const FilterScreen(),
            ),
          ],
        ),
        // 驱动模块
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/driver',
              builder: (context, state) => const DriverScreen(),
            ),
          ],
        ),
        // 配置模块
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/config',
              builder: (context, state) => const ConfigScreen(),
            ),
          ],
        ),
      ],
    ),
    // 格式文件页面（独立页面）
    GoRoute(
      path: '/format',
      builder: (context, state) => const FormatScreen(),
    ),
    // 指针批量调试页面（独立页面）
    GoRoute(
      path: '/pointer-debug',
      builder: (context, state) => const PointerDebugScreen(),
    ),
  ],
);
