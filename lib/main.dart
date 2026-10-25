import 'dart:async';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import 'consts.dart';
import 'pages/dashboard_page.dart';
import 'pages/supply_list_page.dart';
import 'service/settings_service.dart';
import 'service/widget_service.dart';

/// 全局 Navigator key：小部件深链在 App 生命周期的任意时刻入栈
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// v1.6：小部件点击深链——直达消耗物资列表「临期+过期」筛选
const String kWidgetUrgentUri = 'jiacangben://supplies?filter=urgent';

void main() {
  runApp(const JiaCangBenApp());
}

class JiaCangBenApp extends StatefulWidget {
  const JiaCangBenApp({super.key});

  @override
  State<JiaCangBenApp> createState() => _JiaCangBenAppState();
}

class _JiaCangBenAppState extends State<JiaCangBenApp> with WidgetsBindingObserver {
  StreamSubscription<Uri?>? _widgetClickSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
    // 热启动（App 在后台时点小部件）：URI 经流送达
    _widgetClickSub = HomeWidget.widgetClicked.listen(_routeWidgetLaunch);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetClickSub?.cancel();
    super.dispose();
  }

  /// 冷启动：刷新小部件快照 + 处理「由小部件启动」的深链 + 载入字体档位
  Future<void> _bootstrap() async {
    final settings = SettingsService();
    SettingsService.fontScale.value = await settings.getFontScale();
    await WidgetService().refresh();
    _routeWidgetLaunch(await HomeWidget.initiallyLaunchedFromHomeWidget());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // v1.6：回前台即刷新小部件快照（编辑/领用/删除后无需手动触发）
    if (state == AppLifecycleState.resumed) {
      WidgetService().refresh();
    }
  }

  void _routeWidgetLaunch(Uri? uri) {
    if (uri == null || uri.toString() != kWidgetUrgentUri) return;
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => const HomeSupplyListPage(initialFilter: SupplyStatusFilter.urgent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // v1.8：字体档位即时生效（ValueListenableBuilder 重建 MaterialApp 的 textScaler）
    return ValueListenableBuilder<double>(
      valueListenable: SettingsService.fontScale,
      builder: (context, scale, _) => MaterialApp(
        title: kAppName,
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8D6E63)),
        ),
        home: const HomeDashboardPage(),
      ),
    );
  }
}
