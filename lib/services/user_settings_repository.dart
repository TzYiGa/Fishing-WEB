import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:fishing_map/models/map_view_settings.dart";
import "package:fishing_map/models/user_firestore_summary.dart";
import "package:fishing_map/models/user_profile_extra.dart";

/// Firestore `users/{uid}` 個人資料讀取的逾時；逾時後改讀 SDK 離線快取，避免卡住 UI。
/// 本地／冷啟連線異常時 8～12s 仍可能發生；App 側另有 SharedPreferences 快取第一道防線。
const Duration firestoreProfileExtraFetchTimeout = Duration(seconds: 8);

class UserSettingsRepository {
  UserSettingsRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection("users").doc(uid);

  static bool _offlineLikeFirestore(FirebaseException e) {
    final c = e.code.toLowerCase();
    if (c == "unavailable" || c == "deadline-exceeded") return true;
    final m = e.message?.toLowerCase() ?? "";
    return m.contains("offline") || m.contains("client is offline");
  }

  Future<MapViewSettings> loadMapSettings(String uid) async {
    try {
      final snap = await _doc(uid).get();
      return MapViewSettings.fromMap(snap.data());
    } on FirebaseException catch (e) {
      if (!_offlineLikeFirestore(e)) rethrow;
      try {
        final cached = await _doc(uid).get(
          const GetOptions(source: Source.cache),
        );
        if (cached.exists) return MapViewSettings.fromMap(cached.data());
      } on FirebaseException catch (_) {
        // 快取不可用時退回預設。
      }
      return const MapViewSettings();
    }
  }

  Future<void> saveMapSettings(String uid, MapViewSettings settings) async {
    try {
      await _doc(uid).set(settings.toMap(), SetOptions(merge: true));
    } on FirebaseException catch (e) {
      if (!_offlineLikeFirestore(e)) rethrow;
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _profileDocFromCacheBestEffort(
    String uid,
  ) =>
      _doc(uid).get(const GetOptions(source: Source.cache));

  Future<UserProfileExtra> loadProfileExtra(String uid) async {
    try {
      final snap = await _doc(uid)
          .get()
          .timeout(firestoreProfileExtraFetchTimeout);
      return UserProfileExtra.fromFirestoreMap(snap.data());
    } on TimeoutException {
      try {
        final cached = await _profileDocFromCacheBestEffort(uid);
        return UserProfileExtra.fromFirestoreMap(cached.data());
      } on FirebaseException catch (_) {
        return const UserProfileExtra();
      }
    } on FirebaseException catch (e) {
      if (!_offlineLikeFirestore(e)) rethrow;
      try {
        final cached = await _profileDocFromCacheBestEffort(uid);
        return UserProfileExtra.fromFirestoreMap(cached.data());
      } on FirebaseException catch (_) {
        return const UserProfileExtra();
      }
    }
  }

  /// 列出所有 `users/*` 文件（僅含曾寫入過 Firestore 的帳號；無文件者不會出現）。
  Stream<List<UserFirestoreSummary>> watchAllUserSummaries() {
    return _db.collection("users").snapshots().map((snap) {
      final list = snap.docs.map(UserFirestoreSummary.fromDoc).toList();
      list.sort((a, b) => a.uid.compareTo(b.uid));
      return list;
    });
  }

  Future<void> saveProfileExtra(String uid, UserProfileExtra extra) async {
    final cleanBio = extra.bio.trim();
    final map = <String, dynamic>{
      "profileUpdatedAt": FieldValue.serverTimestamp(),
    };
    if (cleanBio.isEmpty) {
      map["profileBio"] = FieldValue.delete();
    } else {
      map["profileBio"] = cleanBio;
    }
    try {
      await _doc(uid).set(map, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      if (!_offlineLikeFirestore(e)) rethrow;
    }
  }
}
