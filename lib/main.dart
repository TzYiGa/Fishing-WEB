import "package:fishing_map/core/auth/auth_bootstrap.dart";
import "package:fishing_map/screens/firebase_setup_screen.dart";
import "package:fishing_map/screens/map_home_screen.dart";
import "package:fishing_map/models/map_view_settings.dart";
import "package:fishing_map/services/auth_service.dart";
import "package:fishing_map/services/spot_repository.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:firebase_core/firebase_core.dart";
import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";

import "firebase_options.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  late final FirebaseOptions options;
  try {
    options = DefaultFirebaseOptions.web;
  } catch (e, st) {
    runApp(FirebaseSetupScreen(message: "$e\n$st"));
    return;
  }

  try {
    await Firebase.initializeApp(options: options);
    await AuthBootstrap.ensureFirebasePersistence();
  } catch (e, st) {
    runApp(
      MaterialApp(
        title: "釣魚地圖",
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text("Firebase 初始化失敗。\n請確認 firebase_options.dart 為 FlutterFire "
                  "CLI 正確輸出，且 Firebase 專案已啟用 Web App。\n\n$e"),
            ),
          ),
        ),
      ),
    );
    return;
  }

  final repo = SpotRepository();
  await repo.preloadFromDisk();

  runApp(FishingApp(
    auth: AuthService(),
    repo: repo,
  ));
}

class FishingApp extends StatelessWidget {
  FishingApp({super.key, required this.auth, required this.repo});

  final AuthService auth;
  final SpotRepository repo;
  final ValueNotifier<MapViewSettings> mapSettings =
      ValueNotifier(const MapViewSettings());

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF0284c7));
    final theme = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
    );

    return MaterialApp(
      title: "釣魚地圖",
      debugShowCheckedModeBanner: false,
      theme: theme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale("en"),
        Locale("zh", "TW"),
        Locale("zh", "CN"),
      ],
      home: StreamBuilder<User?>(
        stream: auth.authChanges,
        builder: (context, snapshot) {
          final waitingWithNoUserYet = snapshot.connectionState ==
                  ConnectionState.waiting &&
              snapshot.data == null;
          if (waitingWithNoUserYet) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          return MapHomeScreen(
            auth: auth,
            repo: repo,
            settingsListenable: mapSettings,
          );
        },
      ),
    );
  }
}
