import "dart:async";
import "dart:convert";
import "dart:typed_data";

import "package:fishing_map/models/fishing_spot.dart";
import "package:fishing_map/models/spot_category.dart";
import "package:fishing_map/models/spot_comment.dart";
import "package:fishing_map/models/spot_environment_snapshot.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:uuid/uuid.dart";

String? _trimOrNullDisk(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

class SpotRepository {
  SpotRepository() {
    // 每次呼叫都回傳「新 async* Stream」會觸發 StreamBuilder 重綁、取消舊訂閱，
    // 在資料 yield 前被取消時地圖會一直收到 []；F5 / 父層重建後常見此情形。
    _watchSpotsStream = Stream<List<FishingSpot>>.multi((emitter) async {
      await _ensureLoaded();
      emitter.add(_sortedSpots(_spots));
      await emitter.addStream(_spotsCtrl.stream);
    });
  }

  final _uuid = const Uuid();
  static const _spotsKey = "local.spots";
  static const _commentsKey = "local.comments";

  final _spotsCtrl = StreamController<List<FishingSpot>>.broadcast();
  final Map<String, StreamController<List<SpotComment>>> _commentCtrls = {};

  bool _loaded = false;
  final List<FishingSpot> _spots = [];
  final Map<String, List<SpotComment>> _commentsBySpot = {};

  late final Stream<List<FishingSpot>> _watchSpotsStream;

  /// 單例式串流引用，避免 Widget 重建時換 stream 導致載入被取消。
  Stream<List<FishingSpot>> watchSpots() => _watchSpotsStream;

  /// 在 [runApp] 前呼叫，讓首屏地圖不需等 async 才讀到 SharedPreferences。
  Future<void> preloadFromDisk() async {
    await _ensureLoaded();
  }

  /// [preloadFromDisk]（或曾觸發過 [watchSpots]）後可讀；否則為空列表。
  List<FishingSpot> spotsSnapshotIfLoaded() {
    if (!_loaded) return const [];
    return _sortedSpots(_spots);
  }

  Future<String> createDraftSpot({
    required FishingSpot draft,
    required String userId,
  }) async {
    await _ensureLoaded();
    final id = _uuid.v4();
    _spots.add(
        FishingSpot(
        id: id,
        lat: draft.lat,
        lng: draft.lng,
        name: draft.name,
        description: draft.description,
        userId: userId,
        photoUrls: const [],
        createdAt: DateTime.now(),
        categoryId: draft.categoryId,
        environmentAtPost: draft.environmentAtPost,
        fishingAt: draft.fishingAt,
        cwaLinkedTideStationId: draft.cwaLinkedTideStationId,
        cwaLinkedTideStationNameZh: draft.cwaLinkedTideStationNameZh,
        cwaLinkedBuoyStationId: draft.cwaLinkedBuoyStationId,
        cwaLinkedBuoyStationNameZh: draft.cwaLinkedBuoyStationNameZh,
        cwaLinkedStationId: draft.cwaLinkedStationId,
        cwaLinkedStationNameZh: draft.cwaLinkedStationNameZh,
      ),
    );
    await _persist();
    _emitSpots();
    return id;
  }

  Future<void> attachPhotoUrls(String spotId, List<String> urls) async {
    await _ensureLoaded();
    if (urls.isEmpty) return;
    final idx = _spots.indexWhere((s) => s.id == spotId);
    if (idx < 0) return;
    final s = _spots[idx];
    _spots[idx] = FishingSpot(
      id: s.id,
      lat: s.lat,
      lng: s.lng,
      name: s.name,
      description: s.description,
      userId: s.userId,
      photoUrls: [...s.photoUrls, ...urls],
      createdAt: s.createdAt,
      categoryId: s.categoryId,
      environmentAtPost: s.environmentAtPost,
      fishingAt: s.fishingAt,
      cwaLinkedTideStationId: s.cwaLinkedTideStationId,
      cwaLinkedTideStationNameZh: s.cwaLinkedTideStationNameZh,
      cwaLinkedBuoyStationId: s.cwaLinkedBuoyStationId,
      cwaLinkedBuoyStationNameZh: s.cwaLinkedBuoyStationNameZh,
      cwaLinkedStationId: s.cwaLinkedStationId,
      cwaLinkedStationNameZh: s.cwaLinkedStationNameZh,
    );
    await _persist();
    _emitSpots();
  }

  Future<void> setEnvironmentAtPost(
    String spotId,
    SpotEnvironmentSnapshot snapshot,
  ) async {
    await _ensureLoaded();
    final idx = _spots.indexWhere((s) => s.id == spotId);
    if (idx < 0) return;
    final s = _spots[idx];
    _spots[idx] = FishingSpot(
      id: s.id,
      lat: s.lat,
      lng: s.lng,
      name: s.name,
      description: s.description,
      userId: s.userId,
      photoUrls: s.photoUrls,
      createdAt: s.createdAt,
      categoryId: s.categoryId,
      environmentAtPost: snapshot,
      fishingAt: s.fishingAt,
      cwaLinkedTideStationId: s.cwaLinkedTideStationId,
      cwaLinkedTideStationNameZh: s.cwaLinkedTideStationNameZh,
      cwaLinkedBuoyStationId: s.cwaLinkedBuoyStationId,
      cwaLinkedBuoyStationNameZh: s.cwaLinkedBuoyStationNameZh,
      cwaLinkedStationId: s.cwaLinkedStationId,
      cwaLinkedStationNameZh: s.cwaLinkedStationNameZh,
    );
    await _persist();
    _emitSpots();
  }

  /// 於擷取海象前寫入最近潮位站／浮標代號（避免 API 失敗時仍無綁定紀錄）。
  Future<void> setCwaTideBuoyStationLinks(
    String spotId, {
    String? tideStationId,
    String? tideStationNameZh,
    String? buoyStationId,
    String? buoyStationNameZh,
  }) async {
    await _ensureLoaded();
    final idx = _spots.indexWhere((s) => s.id == spotId);
    if (idx < 0) return;
    final s = _spots[idx];
    _spots[idx] = FishingSpot(
      id: s.id,
      lat: s.lat,
      lng: s.lng,
      name: s.name,
      description: s.description,
      userId: s.userId,
      photoUrls: s.photoUrls,
      createdAt: s.createdAt,
      categoryId: s.categoryId,
      environmentAtPost: s.environmentAtPost,
      fishingAt: s.fishingAt,
      cwaLinkedTideStationId: tideStationId ?? s.cwaLinkedTideStationId,
      cwaLinkedTideStationNameZh: tideStationNameZh ?? s.cwaLinkedTideStationNameZh,
      cwaLinkedBuoyStationId: buoyStationId ?? s.cwaLinkedBuoyStationId,
      cwaLinkedBuoyStationNameZh: buoyStationNameZh ?? s.cwaLinkedBuoyStationNameZh,
      cwaLinkedStationId: s.cwaLinkedStationId,
      cwaLinkedStationNameZh: s.cwaLinkedStationNameZh,
    );
    await _persist();
    _emitSpots();
  }

  Future<String> uploadSpotPhoto({
    required String spotId,
    required Uint8List bytes,
    required String mime,
  }) async {
    final b64 = base64Encode(bytes);
    return "data:$mime;base64,$b64";
  }

  Stream<List<SpotComment>> watchComments(String spotId) async* {
    await _ensureLoaded();
    _commentCtrls.putIfAbsent(
      spotId,
      () => StreamController<List<SpotComment>>.broadcast(),
    );
    yield _sortedComments(_commentsBySpot[spotId] ?? const []);
    yield* _commentCtrls[spotId]!.stream;
  }

  Future<void> addComment({
    required String spotId,
    required SpotComment comment,
    required String userId,
    required String authorLabel,
  }) async {
    await _ensureLoaded();
    final list = _commentsBySpot.putIfAbsent(spotId, () => []);
    list.add(
      SpotComment(
        id: _uuid.v4(),
        text: comment.text,
        userId: userId,
        authorLabel: authorLabel,
        createdAt: DateTime.now(),
      ),
    );
    await _persist();
    _emitComments(spotId);
  }

  /// 僅留言作者或管理員可刪除（由呼叫端傳入 [requesterIsAdmin]，本機儲存仍應在正式上線時改由後端驗證）。
  Future<void> deleteComment({
    required String spotId,
    required String commentId,
    required String requesterUserId,
    required bool requesterIsAdmin,
  }) async {
    await _ensureLoaded();
    final list = _commentsBySpot[spotId];
    if (list == null) return;
    final idx = list.indexWhere((c) => c.id == commentId);
    if (idx < 0) return;
    final target = list[idx];
    final isAuthor = target.userId == requesterUserId;
    if (!isAuthor && !requesterIsAdmin) {
      throw StateError("僅能刪除自己的留言，或由管理員刪除");
    }
    list.removeAt(idx);
    await _persist();
    _emitComments(spotId);
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();

    final spotsRaw = prefs.getString(_spotsKey);
    if (spotsRaw != null && spotsRaw.isNotEmpty) {
      final decoded = jsonDecode(spotsRaw);
      if (decoded is List) {
        _spots
          ..clear()
          ..addAll(
            decoded.whereType<Map>().map((m) {
              final map = Map<String, dynamic>.from(m);
              final rawCat = map["categoryId"] as String?;
              return FishingSpot(
                id: map["id"] as String? ?? "",
                lat: (map["lat"] as num?)?.toDouble() ?? 0,
                lng: (map["lng"] as num?)?.toDouble() ?? 0,
                name: map["name"] as String? ?? "未命名釣點",
                description: map["description"] as String? ?? "",
                userId: map["userId"] as String? ?? "",
                photoUrls: (map["photoUrls"] as List?)
                        ?.whereType<String>()
                        .toList(growable: false) ??
                    const [],
                createdAt: DateTime.tryParse(map["createdAt"] as String? ?? "") ??
                    DateTime.now(),
                categoryId:
                    spotCategoryById(rawCat)?.id ?? kDefaultSpotCategoryId,
                environmentAtPost: () {
                  final e = map["environmentAtPost"];
                  if (e is Map<String, dynamic>) {
                    return SpotEnvironmentSnapshot.fromJson(e);
                  }
                  if (e is Map) {
                    return SpotEnvironmentSnapshot.fromJson(
                      Map<String, dynamic>.from(e),
                    );
                  }
                  return null;
                }(),
                fishingAt: () {
                  final raw = map["fishingAt"] as String?;
                  if (raw == null || raw.isEmpty) return null;
                  return DateTime.tryParse(raw);
                }(),
                cwaLinkedTideStationId: _trimOrNullDisk(map["cwaLinkedTideStationId"]) ??
                    _trimOrNullDisk(map["cwaLinkedStationId"]),
                cwaLinkedTideStationNameZh:
                    _trimOrNullDisk(map["cwaLinkedTideStationNameZh"]) ??
                        _trimOrNullDisk(map["cwaLinkedStationNameZh"]),
                cwaLinkedBuoyStationId: _trimOrNullDisk(map["cwaLinkedBuoyStationId"]),
                cwaLinkedBuoyStationNameZh:
                    _trimOrNullDisk(map["cwaLinkedBuoyStationNameZh"]),
                cwaLinkedStationId: _trimOrNullDisk(map["cwaLinkedStationId"]),
                cwaLinkedStationNameZh: _trimOrNullDisk(map["cwaLinkedStationNameZh"]),
              );
            }),
          );
      }
    }

    final commentsRaw = prefs.getString(_commentsKey);
    if (commentsRaw != null && commentsRaw.isNotEmpty) {
      final decoded = jsonDecode(commentsRaw);
      if (decoded is Map) {
        _commentsBySpot.clear();
        for (final entry in decoded.entries) {
          final key = entry.key.toString();
          final value = entry.value;
          if (value is! List) continue;
          _commentsBySpot[key] = value.whereType<Map>().map((m) {
            final map = Map<String, dynamic>.from(m);
            return SpotComment(
              id: map["id"] as String? ?? "",
              text: map["text"] as String? ?? "",
              userId: map["userId"] as String? ?? "",
              authorLabel: map["authorLabel"] as String? ?? "匿名",
              createdAt:
                  DateTime.tryParse(map["createdAt"] as String? ?? "") ?? DateTime.now(),
            );
          }).toList(growable: true);
        }
      }
    }

    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _spotsKey,
      jsonEncode([
        for (final s in _spots)
          {
            "id": s.id,
            "lat": s.lat,
            "lng": s.lng,
            "name": s.name,
            "description": s.description,
            "userId": s.userId,
            "photoUrls": s.photoUrls,
            "categoryId": s.categoryId,
            if (s.environmentAtPost != null)
              "environmentAtPost": s.environmentAtPost!.toJson(),
            if (s.fishingAt != null)
              "fishingAt": s.fishingAt!.toUtc().toIso8601String(),
            if (s.cwaLinkedTideStationId != null)
              "cwaLinkedTideStationId": s.cwaLinkedTideStationId,
            if (s.cwaLinkedTideStationNameZh != null)
              "cwaLinkedTideStationNameZh": s.cwaLinkedTideStationNameZh,
            if (s.cwaLinkedBuoyStationId != null)
              "cwaLinkedBuoyStationId": s.cwaLinkedBuoyStationId,
            if (s.cwaLinkedBuoyStationNameZh != null)
              "cwaLinkedBuoyStationNameZh": s.cwaLinkedBuoyStationNameZh,
            if (s.cwaLinkedStationId != null)
              "cwaLinkedStationId": s.cwaLinkedStationId,
            if (s.cwaLinkedStationNameZh != null)
              "cwaLinkedStationNameZh": s.cwaLinkedStationNameZh,
            "createdAt": s.createdAt.toIso8601String(),
          },
      ]),
    );
    await prefs.setString(
      _commentsKey,
      jsonEncode({
        for (final e in _commentsBySpot.entries)
          e.key: [
            for (final c in e.value)
              {
                "id": c.id,
                "text": c.text,
                "userId": c.userId,
                "authorLabel": c.authorLabel,
                "createdAt": c.createdAt.toIso8601String(),
              },
          ],
      }),
    );
  }

  List<FishingSpot> _sortedSpots(List<FishingSpot> items) {
    final copy = [...items];
    copy.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return copy;
  }

  List<SpotComment> _sortedComments(List<SpotComment> items) {
    final copy = [...items];
    copy.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return copy;
  }

  void _emitSpots() {
    if (_spotsCtrl.isClosed) return;
    _spotsCtrl.add(_sortedSpots(_spots));
  }

  void _emitComments(String spotId) {
    final ctrl = _commentCtrls.putIfAbsent(
      spotId,
      () => StreamController<List<SpotComment>>.broadcast(),
    );
    if (ctrl.isClosed) return;
    ctrl.add(_sortedComments(_commentsBySpot[spotId] ?? const []));
  }
}
