/// Firebase Authentication 使用者一列（由 Admin Callable 回傳）。
class AdminAuthUserRow {
  const AdminAuthUserRow({
    required this.uid,
    this.email,
    this.displayName,
    required this.emailVerified,
    required this.disabled,
    this.creationTime,
    this.lastSignInTime,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final bool emailVerified;
  final bool disabled;
  final String? creationTime;
  final String? lastSignInTime;

  factory AdminAuthUserRow.fromJson(Map<String, dynamic> j) {
    return AdminAuthUserRow(
      uid: j["uid"] as String? ?? "",
      email: j["email"] as String?,
      displayName: j["displayName"] as String?,
      emailVerified: j["emailVerified"] as bool? ?? false,
      disabled: j["disabled"] as bool? ?? false,
      creationTime: j["creationTime"] as String?,
      lastSignInTime: j["lastSignInTime"] as String?,
    );
  }
}

class AdminAuthListPage {
  const AdminAuthListPage({
    required this.users,
    this.nextPageToken,
  });

  final List<AdminAuthUserRow> users;
  final String? nextPageToken;
}
