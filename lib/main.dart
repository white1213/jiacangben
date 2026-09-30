import 'package:flutter/material.dart';

import 'consts.dart';
import 'pages/dashboard_page.dart';

void main() {
  runApp(const JiaCangBenApp());
}

class JiaCangBenApp extends StatelessWidget {
  const JiaCangBenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8D6E63)),
      ),
      home: const HomeDashboardPage(),
    );
  }
}
