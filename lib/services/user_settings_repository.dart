import "package:cloud_firestore/cloud_firestore.dart";
import "package:fishing_map/models/map_view_settings.dart";

class UserSettingsRepository {
  UserSettingsRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection("users").doc(uid);

  Future<MapViewSettings> loadMapSettings(String uid) async {
    final snap = await _doc(uid).get();
    return MapViewSettings.fromMap(snap.data());
  }

  Future<void> saveMapSettings(String uid, MapViewSettings settings) {
    return _doc(uid).set(settings.toMap(), SetOptions(merge: true));
  }
}
