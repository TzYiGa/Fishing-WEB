import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";

/// Web 將 session 保存在瀏覽器長期儲存（Firebase JS SDK：`LOCAL`，實際多為 IndexedDB）；
/// 不可在此寫入密碼或由客戶端自行發明長效 JWT——由 Firebase Refresh Token／ID Token 管理。
abstract final class AuthBootstrap {
  /// 必須在 [Firebase.initializeApp] 後、第一次 [signIn] 前呼叫（Web）。
  static Future<void> ensureFirebasePersistence() async {
    if (!kIsWeb) return;
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }
}
