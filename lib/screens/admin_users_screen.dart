import "package:fishing_map/screens/admin_auth_users_tab.dart";
import "package:fishing_map/screens/admin_firestore_users_tab.dart";
import "package:fishing_map/services/admin_auth_api.dart";
import "package:fishing_map/services/user_settings_repository.dart";
import "package:flutter/material.dart";

/// 管理員：Authentication（Admin SDK）與 Firestore `users` 分頁。
class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({
    super.key,
    required this.settingsRepo,
    required this.adminAuthApi,
  });

  final UserSettingsRepository settingsRepo;
  final AdminAuthApi adminAuthApi;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("管理使用者"),
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.badge_outlined),
                text: "Auth 帳戶",
              ),
              Tab(
                icon: Icon(Icons.description_outlined),
                text: "Firestore",
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            AdminAuthUsersTab(api: adminAuthApi),
            AdminFirestoreUsersTab(settingsRepo: settingsRepo),
          ],
        ),
      ),
    );
  }
}
