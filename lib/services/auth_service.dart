import "package:fishing_map/core/network/authorized_http.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;

/// Firebase Auth 會自動處理：登入態持久化（Web：`Persistence.LOCAL`）、Refresh Token（由 SDK／瀏覽器儲存，勿手寫密碼到 LocalStorage）、
/// 短命 ID Token（`getIdToken`）供 Bearer API。
///
/// **重要：** `FirebaseAuth.authStateChanges()` 的 broadcast 對「較晚訂閱」的監聽者**不會回放**第一期事件，
/// 因此此處對外提供的 [authChanges] 使用 [Stream.multi]，每個監聽者會先收到 [FirebaseAuth.currentUser] 快照再接上底層事件流，
/// 否則 F5 後 [StreamBuilder] 可能永遠停在 `waiting`／`null`（畫面上像被登出）。
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance {
    _firebaseAuthDelegate = _auth.authStateChanges();
    _firebaseTokenDelegate = _auth.idTokenChanges();

    final adminMapped =
        _firebaseTokenDelegate.asyncMap(_hasAdminClaim);

    _authChangesReplayed =
        Stream<User?>.multi((emitter) async {
      emitter.add(_auth.currentUser);
      await emitter.addStream(_firebaseAuthDelegate);
    });
    _adminChangesReplayed = Stream<bool>.multi((emitter) async {
      emitter.add(await _hasAdminClaim(_auth.currentUser));
      await emitter.addStream(adminMapped);
    });

    _syncGuestFlag(_auth.currentUser);
    _firebaseAuthDelegate.listen(_syncGuestFlag);
  }

  final FirebaseAuth _auth;
  late final Stream<User?> _firebaseAuthDelegate;
  late final Stream<User?> _firebaseTokenDelegate;

  late final Stream<User?> _authChangesReplayed;
  late final Stream<bool> _adminChangesReplayed;

  final ValueNotifier<bool> _guestMode = ValueNotifier(true);

  void _syncGuestFlag(User? user) {
    _guestMode.value = user == null;
  }

  User? get currentUser => _auth.currentUser;

  /// 含「目前快照 + 後續變更」，適合全域 [StreamBuilder]。
  Stream<User?> get authChanges => _authChangesReplayed;

  Stream<bool> get adminChanges => _adminChangesReplayed;

  ValueListenable<bool> get guestModeListenable => _guestMode;

  bool get isGuestMode => _guestMode.value;

  AuthorizedHttpFacade authorizedHttp({http.Client? client}) =>
      AuthorizedHttpFacade(client: client, resolveIdToken: getIdToken);

  Future<String?> getIdToken({bool forceRefresh = false}) {
    final user = _auth.currentUser;
    if (user == null) return Future.value(null);
    return user.getIdToken(forceRefresh);
  }

  Future<UserCredential> signInWithEmail(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> registerWithEmail(String email, String password) {
    return _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<bool> isCurrentUserAdmin() async {
    return _hasAdminClaim(_auth.currentUser);
  }

  Future<bool> _hasAdminClaim(User? user) async {
    if (user == null) return false;
    final token = await user.getIdTokenResult(true);
    return token.claims?["admin"] == true;
  }

  String labelFor(User? user) {
    if (user == null) return "訪客";
    return user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : (user.email ?? user.uid.substring(0, 6));
  }
}
