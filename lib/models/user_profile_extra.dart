/// 與 [MapViewSettings] 一併存放在 Firestore `users/{uid}`（merge），不影響現有欄位。
class UserProfileExtra {
  const UserProfileExtra({this.bio = ""});

  final String bio;

  UserProfileExtra copyWith({String? bio}) {
    return UserProfileExtra(bio: bio ?? this.bio);
  }

  static UserProfileExtra fromFirestoreMap(Map<String, dynamic>? data) {
    if (data == null) return const UserProfileExtra();
    final b = data["profileBio"];
    if (b is String) return UserProfileExtra(bio: b);
    return const UserProfileExtra();
  }
}
