import "package:flutter/material.dart";

/// Firebase 尚未透過 FlutterFire CLI 設定時顯示。
class FirebaseSetupScreen extends StatelessWidget {
  const FirebaseSetupScreen({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0284c7)),
      useMaterial3: true,
    );
    return MaterialApp(
      title: "釣魚地圖",
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.map_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    "需要設定 Firebase",
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "請在終端機執行：\n\ndart pub global activate flutterfire_cli\nflutterfire configure\n\n"
                    "產出的 lib/firebase_options.dart 將取代占位檔。",
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 16),
                    Text(message!, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
