import "package:firebase_auth/firebase_auth.dart";

/// 未來將 Google／Apple OAuth 接到此類，避免把所有登入細節堆在 UI 或小工具裡。
/// 請依 [AUTH_SESSION.md] 接上 `google_sign_in`／`sign_in_with_apple` 等套件。
abstract class FederatedAuthPort {
  FirebaseAuth get firebaseAuth;

  Future<UserCredential> signInWithGoogle();

  Future<UserCredential> signInWithAppleWebOrMobile();
}
