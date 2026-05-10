import "package:cloud_firestore/cloud_firestore.dart";
import "package:fishing_map/models/spot_category.dart";
import "package:fishing_map/models/spot_environment_snapshot.dart";

class FishingSpot {
  FishingSpot({
    required this.id,
    required this.lat,
    required this.lng,
    required this.name,
    required this.description,
    required this.userId,
    required this.photoUrls,
    required this.createdAt,
    required this.categoryId,
    this.environmentAtPost,
    this.fishingAt,
    this.cwaLinkedTideStationId,
    this.cwaLinkedTideStationNameZh,
    this.cwaLinkedBuoyStationId,
    this.cwaLinkedBuoyStationNameZh,
    this.cwaLinkedStationId,
    this.cwaLinkedStationNameZh,
  });

  final String id;
  final double lat;
  final double lng;
  final String name;
  final String description;
  final String userId;
  final List<String> photoUrls;
  final DateTime createdAt;

  /// 與 [kSpotCategoryOptions] 的 id 對應（例 `1-2`）。
  final String categoryId;

  /// 發文流程結束時擷取的氣象／海象快照（離線瀏覽仍可看當時狀況）。
  final SpotEnvironmentSnapshot? environmentAtPost;

  /// 使用者填寫的出釣日期時間（用於擷取該時段氣象）；舊資料可能為 null。
  final DateTime? fishingAt;

  /// 最近潮位站 [StationID]（與 [cwaLinkedBuoyStationId] 分開擷取 O-B0075）。
  final String? cwaLinkedTideStationId;

  final String? cwaLinkedTideStationNameZh;

  /// 最近浮標／浮球站 [StationID]。
  final String? cwaLinkedBuoyStationId;

  final String? cwaLinkedBuoyStationNameZh;

  /// 舊版單一綁定代號；讀檔時若無 [cwaLinkedTideStationId] 則視為潮位站代號。
  final String? cwaLinkedStationId;

  final String? cwaLinkedStationNameZh;

  factory FishingSpot.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data()!;
    final geo = m["geo"] as GeoPoint? ?? GeoPoint(0, 0);
    final photos = <String>[];
    final rawPhotos = m["photoUrls"];
    if (rawPhotos is List) {
      for (final e in rawPhotos) {
        if (e is String) photos.add(e);
      }
    }
    final created = (m["createdAt"] as Timestamp?)?.toDate() ?? DateTime.now();
    final rawCat = m["categoryId"] as String? ?? m["category"] as String?;
    final dynamic rawEnv = m["environmentAtPost"];
    return FishingSpot(
      id: doc.id,
      lat: geo.latitude,
      lng: geo.longitude,
      name: (m["name"] as String?) ?? "未命名釣點",
      description: (m["description"] as String?) ?? "",
      userId: (m["userId"] as String?) ?? "",
      photoUrls: photos,
      createdAt: created,
      categoryId: spotCategoryById(rawCat)?.id ?? kDefaultSpotCategoryId,
      environmentAtPost: rawEnv is Map<String, dynamic>
          ? SpotEnvironmentSnapshot.fromJson(rawEnv)
          : rawEnv is Map
              ? SpotEnvironmentSnapshot.fromJson(Map<String, dynamic>.from(rawEnv))
              : null,
      fishingAt: () {
        final raw = m["fishingAt"] as String?;
        if (raw == null || raw.isEmpty) return null;
        return DateTime.tryParse(raw);
      }(),
      cwaLinkedTideStationId: _trimOrNull(m["cwaLinkedTideStationId"]) ??
          _trimOrNull(m["cwaLinkedStationId"]),
      cwaLinkedTideStationNameZh: _trimOrNull(m["cwaLinkedTideStationNameZh"]) ??
          _trimOrNull(m["cwaLinkedStationNameZh"]),
      cwaLinkedBuoyStationId: _trimOrNull(m["cwaLinkedBuoyStationId"]),
      cwaLinkedBuoyStationNameZh: _trimOrNull(m["cwaLinkedBuoyStationNameZh"]),
      cwaLinkedStationId: _trimOrNull(m["cwaLinkedStationId"]),
      cwaLinkedStationNameZh: _trimOrNull(m["cwaLinkedStationNameZh"]),
    );
  }

  static String? _trimOrNull(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  Map<String, dynamic> toCreateMap({
    required String userId,
  }) =>
      <String, dynamic>{
        "name": name,
        "description": description,
        "geo": GeoPoint(lat, lng),
        "userId": userId,
        "photoUrls": <String>[],
        "categoryId": categoryId,
        if (environmentAtPost != null)
          "environmentAtPost": environmentAtPost!.toJson(),
        if (fishingAt != null) "fishingAt": fishingAt!.toUtc().toIso8601String(),
        if (cwaLinkedTideStationId != null)
          "cwaLinkedTideStationId": cwaLinkedTideStationId,
        if (cwaLinkedTideStationNameZh != null)
          "cwaLinkedTideStationNameZh": cwaLinkedTideStationNameZh,
        if (cwaLinkedBuoyStationId != null)
          "cwaLinkedBuoyStationId": cwaLinkedBuoyStationId,
        if (cwaLinkedBuoyStationNameZh != null)
          "cwaLinkedBuoyStationNameZh": cwaLinkedBuoyStationNameZh,
        if (cwaLinkedStationId != null)
          "cwaLinkedStationId": cwaLinkedStationId,
        if (cwaLinkedStationNameZh != null)
          "cwaLinkedStationNameZh": cwaLinkedStationNameZh,
        "createdAt": FieldValue.serverTimestamp(),
      };
}
