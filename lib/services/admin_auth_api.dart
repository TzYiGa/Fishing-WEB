import "package:cloud_functions/cloud_functions.dart";
import "package:fishing_map/config/firebase_functions_config.dart";
import "package:fishing_map/models/admin_auth_user_row.dart";

/// 管理員專用：經 Cloud Functions + Admin SDK 操作 Authentication。
class AdminAuthApi {
  AdminAuthApi({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: kFirebaseFunctionsRegion);

  final FirebaseFunctions _functions;

  Future<AdminAuthListPage> listUsers({
    int maxResults = 100,
    String? pageToken,
  }) async {
    final callable = _functions.httpsCallable("adminListAuthUsers");
    final res = await callable.call(<String, dynamic>{
      "maxResults": maxResults,
      if (pageToken != null && pageToken.isNotEmpty) "pageToken": pageToken,
    });
    final raw = res.data;
    if (raw is! Map) {
      throw StateError("adminListAuthUsers 回傳格式錯誤");
    }
    final map = Map<String, dynamic>.from(raw);
    final usersRaw = map["users"];
    final list = <AdminAuthUserRow>[];
    if (usersRaw is List) {
      for (final e in usersRaw) {
        if (e is Map) {
          list.add(AdminAuthUserRow.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    final next = map["nextPageToken"] as String?;
    return AdminAuthListPage(users: list, nextPageToken: next);
  }

  Future<void> updateUser({
    required String uid,
    String? email,
    required String displayName,
    String? password,
    required bool disabled,
    required bool emailVerified,
  }) async {
    final payload = <String, dynamic>{
      "uid": uid,
      "displayName": displayName,
      "disabled": disabled,
      "emailVerified": emailVerified,
    };
    if (email != null && email.isNotEmpty) {
      payload["email"] = email;
    }
    if (password != null && password.isNotEmpty) {
      payload["password"] = password;
    }

    final callable = _functions.httpsCallable("adminUpdateAuthUser");
    await callable.call(payload);
  }
}

