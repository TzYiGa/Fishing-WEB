import "package:cloud_firestore/cloud_firestore.dart";
import "package:fishing_map/models/spot_category.dart";
import "package:fishing_map/models/spot_environment_snapshot.dart";
import "package:fishing_map/models/spot_entry_kind.dart";
import "package:fishing_map/models/spot_moderation_status.dart";

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
    required List<String> categoryIds,
    this.entryKind = SpotEntryKind.conditionShare,
    this.moderationStatus = SpotModerationStatus.approved,
    this.environmentAtPost,
    this.fishingAt,
    this.cwaLinkedTideStationId,
    this.cwaLinkedTideStationNameZh,
    this.cwaLinkedBuoyStationId,
    this.cwaLinkedBuoyStationNameZh,
    this.cwaLinkedStationId,
    this.cwaLinkedStationNameZh,
  }) : categoryIds = normalizeCategoryIds(categoryIds);

  final String id;
  final double lat;
  final double lng;
  final String name;
  final String description;
  final String userId;
  final List<String> photoUrls;
  final DateTime createdAt;

  /// 可複選之釣場類型 id（`1-1` … `2-3`）；舊資料僅有 [categoryId] 欄位時讀成單一項。
  final List<String> categoryIds;

  /// 向後相容：地圖主色／舊 API 用第一個類型。
  String get categoryId => categoryIds.first;

  /// 釣況分享 vs 固定釣點；舊資料無欄位時視為 [SpotEntryKind.conditionShare]。
  final SpotEntryKind entryKind;

  /// 審核狀態（僅 [SpotEntryKind.fishingPoi] 會用到；釣況分享一律視為公開）。
  final SpotModerationStatus moderationStatus;

  /// 是否顯示在所有人可見的地圖上。
  bool get showsOnPublicMap {
    if (entryKind == SpotEntryKind.conditionShare) return true;
    return moderationStatus == SpotModerationStatus.approved;
  }

  /// 分類篩選：任一勾選類型命中即顯示。
  bool matchesCategoryFilter(Set<String> visibleIds) {
    for (final c in categoryIds) {
      if (visibleIds.contains(c)) return true;
    }
    return false;
  }

  /// 發文流程結束時擷取的氣象／海象快照（離線瀏覽仍可看當時狀況）。
  final SpotEnvironmentSnapshot? environmentAtPost;

  /// 舊欄位；新建立之釣況／釣點可不填。
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
    final geo = m["geo"] as GeoPoint? ?? const GeoPoint(0, 0);
    final photos = <String>[];
    final rawPhotos = m["photoUrls"];
    if (rawPhotos is List) {
      for (final e in rawPhotos) {
        if (e is String) photos.add(e);
      }
    }
    final created = (m["createdAt"] as Timestamp?)?.toDate() ?? DateTime.now();
    final rawCat = m["categoryId"] as String? ?? m["category"] as String?;
    final idsFromDoc = _parseCategoryIdsList(m, fallbackSingle: rawCat);
    final dynamic rawEnv = m["environmentAtPost"];
    final modRaw = m["moderationStatus"] as String?;
    final kindRaw = m["entryKind"] as String?;
    return FishingSpot(
      id: doc.id,
      lat: geo.latitude,
      lng: geo.longitude,
      name: (m["name"] as String?) ?? "未命名釣點",
      description: (m["description"] as String?) ?? "",
      userId: (m["userId"] as String?) ?? "",
      photoUrls: photos,
      createdAt: created,
      categoryIds: idsFromDoc,
      entryKind: SpotEntryKind.parse(kindRaw),
      moderationStatus: SpotModerationStatus.parse(modRaw),
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

  static List<String> _parseCategoryIdsList(
    Map<String, dynamic> m, {
    String? fallbackSingle,
  }) {
    final raw = m["categoryIds"];
    final fromList = <String>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is String && e.trim().isNotEmpty) fromList.add(e.trim());
      }
    }
    if (fromList.isNotEmpty) return normalizeCategoryIds(fromList);
    if (fallbackSingle != null && fallbackSingle.trim().isNotEmpty) {
      return normalizeCategoryIds([fallbackSingle.trim()]);
    }
    return [kDefaultSpotCategoryId];
  }

  static String? _trimOrNull(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  Map<String, dynamic> toCreateMap({
    required String userId,
    required SpotEntryKind entryKind,
    required SpotModerationStatus moderationStatus,
  }) =>
      <String, dynamic>{
        "name": name,
        "description": description,
        "geo": GeoPoint(lat, lng),
        "userId": userId,
        "photoUrls": <String>[],
        "categoryIds": categoryIds,
        "categoryId": categoryId,
        "entryKind": entryKind.firestoreValue,
        "moderationStatus": moderationStatus.firestoreValue,
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

  /// Firestore `update` 用：不可變更 `userId`／`createdAt`／`photoUrls`（照片另用 [SpotRepository.attachPhotoUrls]）。
  Map<String, dynamic> toFirestoreUpdatePayload() {
    final m = <String, dynamic>{
      "name": name,
      "description": description,
      "categoryIds": categoryIds,
      "categoryId": categoryId,
      "geo": GeoPoint(lat, lng),
    };
    if (fishingAt != null) {
      m["fishingAt"] = fishingAt!.toUtc().toIso8601String();
    } else {
      m["fishingAt"] = FieldValue.delete();
    }
    return m;
  }
}
