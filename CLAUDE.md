# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**fscan** is a Flutter mobile application project. This is currently the default Flutter counter app template, serving as a starting point for development.

## Build and Development Commands

```bash
# Run the app in debug mode
flutter run

# Run on a specific device
flutter run -d <device_id>

# Build for release
flutter build apk          # Android APK
flutter build ios          # iOS (requires macOS)
flutter build web          # Web

# Run tests
flutter test               # Run all tests
flutter test test/widget_test.dart  # Run a single test file

# Analyze code for issues
flutter analyze

# Format code
dart format .

# Get/update dependencies
flutter pub get
flutter pub upgrade
```

## Architecture

- **Feature-first architecture**: 按功能模块组织代码
- **Routing**: 使用 go_router 实现底部导航栏和页面切换
- **Entry point**: `main()` 函数运行 `MyApp` 组件
- **State management**: 当前使用简单的 StatelessWidget，可扩展为 BLoC/Riverpod
- **Theming**: Material Design 3 with `ThemeData.fromSeed()`

### 项目结构
```
lib/
├── core/                    # 共享工具和常量
│   └── theme/               # 主题配置
│       ├── app_theme.dart
│       └── theme_provider.dart
├── features/                # 功能模块
│   ├── scan/               # 扫描模块
│   │   └── presentation/screens/scan_screen.dart
│   ├── compare/            # 对比模块
│   │   └── presentation/screens/compare_screen.dart
│   ├── filter/             # 过滤模块
│   │   └── presentation/screens/filter_screen.dart
│   ├── driver/             # 驱动模块
│   │   └── presentation/screens/driver_screen.dart
│   ├── config/             # 配置模块
│   │   └── presentation/screens/config_screen.dart
│   └── home/               # 主页面（底部导航栏）
│       └── presentation/screens/home_screen.dart
├── routing/                # 路由配置
│   └── app_router.dart
└── main.dart               # 入口文件
```

## Key Configuration

- **Flutter SDK**: ^3.12.2
- **Android**: Uses Kotlin DSL for Gradle builds, Java 17 compatibility
- **Linting**: Uses `flutter_lints` package via `analysis_options.yaml`
- **Application ID**: `com.fscan.fscan`

## UI 库

### 已集成的 UI 库

| 库 | 版本 | 说明 |
|---|---|---|
| flutter_screenutil | ^5.9.3 | 屏幕适配，设计尺寸 375x812 |
| google_fonts | ^8.2.0 | 自定义字体，使用 NotoSansSC |
| shimmer | ^3.0.0 | 骨架屏加载效果 |

### 主题配置

统一主题配置位于 `lib/core/theme/app_theme.dart`：
- 亮色/暗色主题
- 默认暗色主题
- 透明 AppBar 样式
- 中文 NotoSansSC 字体

主题切换功能：
- `lib/core/theme/theme_provider.dart` - 主题状态管理
- 配置页面可切换亮色/暗色主题
- 使用 Provider 状态管理

### 使用示例

```dart
// 屏幕适配
Container(
  width: 100.w,    // 宽度适配
  height: 50.h,    // 高度适配
  child: Text(
    '文字',
    style: TextStyle(fontSize: 16.sp), // 字体适配
  ),
)

// 骨架屏
Shimmer.fromColors(
  baseColor: Colors.grey[300]!,
  highlightColor: Colors.grey[100]!,
  child: Container(
    width: 100,
    height: 100,
    color: Colors.white,
  ),
)
```

## Project Structure Guidelines

采用 **Feature-first** 架构，按功能模块组织代码：

```
lib/
├── core/                    # 共享工具和常量
│   ├── constants/           # 常量定义
│   ├── errors/              # 错误处理
│   ├── network/             # 网络层
│   ├── theme/               # 主题配置
│   └── utils/               # 工具函数
├── features/                # 功能模块
│   ├── auth/                # 认证模块
│   │   ├── data/            # 数据层
│   │   │   ├── models/      # 数据模型
│   │   │   ├── repositories/# 仓库实现
│   │   │   └── datasources/ # 数据源
│   │   ├── domain/          # 领域层
│   │   │   ├── entities/    # 实体
│   │   │   ├── repositories/# 仓库接口
│   │   │   └── usecases/    # 用例
│   │   └── presentation/    # 展示层
│   │       ├── bloc/        # 状态管理
│   │       ├── screens/     # 页面
│   │       └── widgets/     # 组件
│   ├── home/
│   └── profile/
├── shared/                  # 共享组件
│   ├── widgets/             # 通用组件
│   └── extensions/          # 扩展方法
├── routing/                 # 路由配置
├── app.dart                 # 应用配置
└── main.dart                # 入口文件
```

## Page/Screen 规范

### 页面结构
- 每个页面继承 `StatelessWidget` 或 `StatefulWidget`
- 页面文件命名：`snake_case_screen.dart`（如 `home_screen.dart`）
- 页面类命名：`PascalCaseScreen`（如 `HomeScreen`）
- 复杂页面拆分为多个 Widget 组件

### 页面生命周期
```dart
class MyScreen extends StatefulWidget {
  const MyScreen({super.key});

  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  @override
  void initState() {
    super.initState();
    // 初始化数据、订阅等
  }

  @override
  void dispose() {
    // 清理资源、取消订阅
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('页面标题')),
      body: const Center(child: Text('内容')),
    );
  }
}
```

### Scaffold 规范
- 每个独立页面使用 `Scaffold` 作为根组件
- 设置合适的 `appBar`、`body`、`floatingActionButton` 等
- 使用 `SafeArea` 处理刘海屏和异形屏

## 路由规范

### 推荐使用 go_router
```yaml
# pubspec.yaml
dependencies:
  go_router: ^14.0.0
```

### 路由配置
```dart
// lib/routing/app_router.dart
import 'package:go_router/go_router.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/profile/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return ProfileScreen(userId: id);
      },
    ),
  ],
);
```

### 路由命名规范
- 路径使用 kebab-case：`/user-profile`
- 命名路由使用 camelCase：`userProfile`
- 路由参数使用 pathParameters：`/user/:id`

### 页面跳转
```dart
// 基本跳转
context.go('/profile/123');

// 带参数跳转
context.go('/profile/$userId');

// 返回上一页
context.pop();

// 替换当前页面（不可返回）
context.push('/login');
```

## 状态管理规范

### 推荐方案
- **简单应用**：Provider 或 Riverpod
- **中大型应用**：BLoC/Cubit
- **快速开发**：GetX（不推荐大型项目）

### BLoC 规范
```dart
// 事件
abstract class AuthEvent {}
class LoginRequested extends AuthEvent {
  final String email;
  final String password;
  LoginRequested({required this.email, required this.password});
}

// 状态
abstract class AuthState {}
class AuthInitial extends AuthState {}
class AuthLoading extends AuthState {}
class AuthSuccess extends AuthState {
  final User user;
  AuthSuccess(this.user);
}
class AuthFailure extends AuthState {
  final String error;
  AuthFailure(this.error);
}

// BLoC
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc() : super(AuthInitial()) {
    on<LoginRequested>(_onLogin);
  }
  
  Future<void> _onLogin(LoginRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await authService.login(event.email, event.password);
      emit(AuthSuccess(user));
    } catch (e) {
      emit(AuthFailure(e.toString()));
    }
  }
}
```

## Widget 设计规范

### 组件拆分原则
- 单一职责：每个 Widget 只做一件事
- 可复用性：通用组件放在 `shared/widgets/`
- 参数化：通过构造函数传入配置

### 命名规范
- Widget 类：`PascalCase`（如 `CustomButton`）
- 私有 Widget：`_PascalCase`（如 `_HeaderSection`）
- 文件名：`snake_case.dart`（如 `custom_button.dart`）

### StatelessWidget vs StatefulWidget
```dart
// StatelessWidget - 无状态
class Greeting extends StatelessWidget {
  final String name;
  const Greeting({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return Text('Hello, $name');
  }
}

// StatefulWidget - 有状态
class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Count: $_count'),
        ElevatedButton(
          onPressed: () => setState(() => _count++),
          child: const Text('Increment'),
        ),
      ],
    );
  }
}
```

## 代码规范

### 命名约定
- 变量/函数：`camelCase`（如 `userName`, `getUserData()`）
- 类：`PascalCase`（如 `UserService`）
- 常量：`kConstantName`（如 `kDefaultPadding`）
- 文件名：`snake_case.dart`（如 `user_service.dart`）

### 导入规范
```dart
// Dart 核心库
import 'dart:convert';
import 'dart:async';

// Flutter 框架
import 'package:flutter/material.dart';

// 第三方包
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// 项目内部（使用相对路径或 package 导入）
import '../core/theme/app_theme.dart';
import 'widgets/custom_button.dart';
```

### 注释规范
```dart
/// 文档注释 - 用于公开 API
/// 
/// 示例:
/// ```dart
/// final user = await fetchUser(123);
/// ```
Future<User> fetchUser(int id) async {
  // 行内注释 - 解释复杂逻辑
  final response = await http.get(Uri.parse('/users/$id'));
  return User.fromJson(response.body);
}

// TODO: 待实现功能
// FIXME: 需要修复的问题
// HACK: 临时解决方案
```

## 测试规范

### 测试文件结构
```
test/
├── unit/              # 单元测试
│   └── features/
├── widget/            # Widget 测试
│   └── features/
└── integration/       # 集成测试
    └── app_test.dart
```

### 命名规范
- 测试文件：`*_test.dart`
- 测试组：`group('ClassName', () { ... })`
- 测试用例：`test('should do something when condition', () { ... })`

### 示例
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/auth/domain/entities/user.dart';

void main() {
  group('User', () {
    test('should create user with valid data', () {
      final user = User(id: 1, name: 'John', email: 'john@example.com');
      expect(user.name, 'John');
    });

    test('should throw when email is invalid', () {
      expect(
        () => User(id: 1, name: 'John', email: 'invalid'),
        throwsArgumentError,
      );
    });
  });
}
```

## 性能优化

### Widget 优化
- 使用 `const` 构造函数
- 避免在 `build()` 中创建新对象
- 使用 `ListView.builder` 而非 `ListView`
- 合理使用 `RepaintBoundary`

### 图片优化
- 使用 `cached_network_image` 缓存网络图片
- 根据屏幕分辨率加载不同尺寸图片
- 使用 WebP 格式减少包大小

### 内存优化
- 及时释放资源（dispose Controller、Stream 等）
- 避免内存泄漏
- 使用 `WeakReference` 处理大对象

## 依赖管理

### 添加依赖
```bash
# 添加依赖
flutter pub add go_router

# 添加开发依赖
flutter pub add --dev build_runner

# 移除依赖
flutter pub remove package_name
```

### 版本约束
```yaml
dependencies:
  # 推荐：兼容版本
  package_a: ^1.2.0
  
  # 精确版本（不推荐）
  package_b: 1.2.3
  
  # Git 依赖（临时使用）
  package_c:
    git:
      url: https://github.com/user/repo.git
      ref: main
```

## 开发流程

1. **创建功能分支**：`git checkout -b feature/user-auth`
2. **编写代码**：遵循上述规范
3. **运行测试**：`flutter test`
4. **代码分析**：`flutter analyze`
5. **格式化代码**：`dart format .`
6. **提交代码**：使用语义化提交信息

## 提交信息规范

```
feat: 添加用户认证功能
fix: 修复登录页面崩溃问题
docs: 更新 README 文档
style: 格式化代码
refactor: 重构用户服务
test: 添加单元测试
chore: 更新依赖版本
```

## 常用第三方包推荐

| 功能 | 推荐包 |
|------|--------|
| 路由 | go_router |
| 状态管理 | provider, flutter_bloc, riverpod |
| 网络请求 | dio, http |
| 本地存储 | shared_preferences, hive, sqflite |
| 依赖注入 | get_it, injectable |
| 代码生成 | freezed, json_serializable |
| 图片加载 | cached_network_image |
| 表单验证 | formz |
| 国际化 | intl, easy_localization |
| 日志 | logger |
