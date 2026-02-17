// main.dart 完整代码
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pages/home_page.dart';

void main() {
  // 1. 初始设置状态栏透明
  // 注意：我们将 icon 亮暗交给主题控制，这里不再硬编码 statusBarIconBrightness
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 定义种子颜色，确保亮暗模式色调一致
    const seedColor = Colors.blueAccent;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TimeAlbum',
      
      // --- 核心设置开始 ---
      
      // 2. 设置系统自动切换主题模式
      themeMode: ThemeMode.system, 

      // 3. 定义浅色模式主题
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light, // 浅色
        ),
      ),

      // 4. 定义深色模式主题
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark, // 深色
        ),
      ),
      
      // --- 核心设置结束 ---
      
      home: const SuperBackupPage(),
    );
  }
}