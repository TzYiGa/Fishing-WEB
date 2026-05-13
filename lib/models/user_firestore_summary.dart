import "package:cloud_firestore/cloud_firestore.dart";
import "package:fishing_map/models/map_view_settings.dart";
import "package:fishing_map/models/user_profile_extra.dart";

/// Firestore `users/{uid}` 一筆摘要（供管理員清單／編輯用）。
class UserFirestoreSummary {
  const UserFirestoreSummary({
    required this.uid,
    required this.mapSettings,
    required this.extra,
    this.updatedAt,
    this.profileUpdatedAt,
  });

  final String uid;
  final MapViewSettings mapSettings;
  final UserProfileExtra extra;
  final DateTime? updatedAt;
  final DateTime? profileUpdatedAt;

  factory UserFirestoreSummary.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data() ?? {};
    return UserFirestoreSummary(
      uid: doc.id,
      mapSettings: MapViewSettings.fromMap(m),
      extra: UserProfileExtra.fromFirestoreMap(m),
      updatedAt: (m["updatedAt"] as Timestamp?)?.toDate(),
      profileUpdatedAt: (m["profileUpdatedAt"] as Timestamp?)?.toDate(),
    );
  }
}
