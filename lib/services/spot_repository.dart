import "dart:async";
import "dart:convert";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:fishing_map/models/fishing_spot.dart";
import "package:fishing_map/models/spot_entry_kind.dart";
import "package:fishing_map/models/spot_moderation_status.dart";
import "package:fishing_map/models/spot_comment.dart";
import "package:fishing_map/models/spot_environment_snapshot.dart";
import "package:flutter/foundation.dart";
import "package:uuid/uuid.dart";

class SpotRepository {
  SpotRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance {
    _watchSpotsStream = _db
        .collection("spots")
        .snapshots()
        .map((snap) {
          final next = <FishingSpot>[];
          for (final doc in snap.docs) {
            try {
              next.add(FishingSpot.fromDoc(doc));
            } catch (e, _) {
              if (kDebugMode) {
                debugPrint("[SpotRepository] 解析釣點失敗(${doc.id}): $e");
              }
            }
          }
          next.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _spots
            ..clear()
            ..addAll(next);
          _loaded = true;
          return List<FishingSpot>.unmodifiable(next);
        })
        .asBroadcastStream();
  }

  final FirebaseFirestore _db;
  final _uuid = const Uuid();
  final List<FishingSpot> _spots = [];
  bool _loaded = false;

  late final Stream<List<FishingSpot>> _watchSpotsStream;

  Stream<List<FishingSpot>> watchSpots() => _watchSpotsStream;

  /// 待審核「固定釣點」（`fishingPoi` 且 `moderationStatus == pending`）。
  Stream<List<FishingSpot>> watchPendingSpots() {
    return _db
        .collection("spots")
        .where("moderationStatus", isEqualTo: SpotModerationStatus.pending.firestoreValue)
        .snapshots()
        .map((snap) {
          final next = <FishingSpot>[];
          for (final doc in snap.docs) {
            try {
              final s = FishingSpot.fromDoc(doc);
              if (s.entryKind != SpotEntryKind.fishingPoi) continue;
              next.add(s);
            } catch (e, _) {
              if (kDebugMode) {
                debugPrint("[SpotRepository] 解析待審釣點失敗(${doc.id}): $e");
              }
            }
          }
          next.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return List<FishingSpot>.unmodifiable(next);
        })
        .asBroadcastStream();
  }

  /// 管理員變更審核狀態（Firestore 規則須為 admin）。
  Future<void> setModerationStatus({
    required String spotId,
    required SpotModerationStatus status,
  }) async {
    await _db.collection("spots").doc(spotId).update({
      "moderationStatus": status.firestoreValue,
    }).timeout(const Duration(seconds: 20));
  }

  /// 已改為純 Firestore 流程；保留 API 以相容既有呼叫端。
  Future<void> preloadFromDisk() async {
    await _ensureLoaded();
  }

  List<FishingSpot> spotsSnapshotIfLoaded() {
    if (!_loaded) return const [];
    return List<FishingSpot>.unmodifiable(_spots);
  }

  Future<String> createDraftSpot({
    required FishingSpot draft,
    required String userId,
    required SpotEntryKind entryKind,
    required SpotModerationStatus moderationStatus,
  }) async {
    await _ensureLoaded();
    final id = _uuid.v4();
    final spot = FishingSpot(
      id: id,
      lat: draft.lat,
      lng: draft.lng,
      name: draft.name,
      description: draft.description,
      userId: userId,
      photoUrls: const [],
      createdAt: DateTime.now(),
      categoryIds: draft.categoryIds,
      entryKind: entryKind,
      moderationStatus: moderationStatus,
      environmentAtPost: draft.environmentAtPost,
      fishingAt: draft.fishingAt,
      cwaLinkedTideStationId: draft.cwaLinkedTideStationId,
      cwaLinkedTideStationNameZh: draft.cwaLinkedTideStationNameZh,
      cwaLinkedBuoyStationId: draft.cwaLinkedBuoyStationId,
      cwaLinkedBuoyStationNameZh: draft.cwaLinkedBuoyStationNameZh,
      cwaLinkedStationId: draft.cwaLinkedStationId,
      cwaLinkedStationNameZh: draft.cwaLinkedStationNameZh,
    );

    await _db
        .collection("spots")
        .doc(id)
        .set(
          spot.toCreateMap(
            userId: userId,
            entryKind: entryKind,
            moderationStatus: moderationStatus,
          ),
        )
        .timeout(const Duration(seconds: 20));
    return id;
  }

  Future<void> attachPhotoUrls(String spotId, List<String> urls) async {
    if (urls.isEmpty) return;
    final ref = _db.collection("spots").doc(spotId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      final current = <String>[];
      final raw = data?["photoUrls"];
      if (raw is List) {
        for (final e in raw) {
          if (e is String) current.add(e);
        }
      }
      tx.update(ref, {"photoUrls": [...current, ...urls]});
    });
  }

  Future<void> setEnvironmentAtPost(
    String spotId,
    SpotEnvironmentSnapshot snapshot,
  ) async {
    await _db.collection("spots").doc(spotId).update({
      "environmentAtPost": snapshot.toJson(),
    });
  }

  Future<void> setCwaTideBuoyStationLinks(
    String spotId, {
    String? tideStationId,
    String? tideStationNameZh,
    String? buoyStationId,
    String? buoyStationNameZh,
  }) async {
    final u = <String, dynamic>{};
    if (tideStationId != null) u["cwaLinkedTideStationId"] = tideStationId;
    if (tideStationNameZh != null) {
      u["cwaLinkedTideStationNameZh"] = tideStationNameZh;
    }
    if (buoyStationId != null) u["cwaLinkedBuoyStationId"] = buoyStationId;
    if (buoyStationNameZh != null) {
      u["cwaLinkedBuoyStationNameZh"] = buoyStationNameZh;
    }
    if (u.isEmpty) return;
    await _db.collection("spots").doc(spotId).update(u);
  }

  Future<String> uploadSpotPhoto({
    required String spotId,
    required Uint8List bytes,
    required String mime,
  }) async {
    final b64 = base64Encode(bytes);
    return "data:$mime;base64,$b64";
  }

  Stream<List<SpotComment>> watchComments(String spotId) {
    return _db
        .collection("spots")
        .doc(spotId)
        .collection("comments")
        .orderBy("createdAt", descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(SpotComment.fromDoc).toList(growable: false));
  }

  Future<void> addComment({
    required String spotId,
    required SpotComment comment,
    required String userId,
    required String authorLabel,
  }) async {
    await _db
        .collection("spots")
        .doc(spotId)
        .collection("comments")
        .add(comment.toCreateMap(userId: userId, authorLabel: authorLabel));
  }

  Future<FishingSpot> updateSpot({
    required FishingSpot spot,
    required String requesterUserId,
    required bool requesterIsAdmin,
    required String name,
    required String description,
    required List<String> categoryIds,
    required double lat,
    required double lng,
    DateTime? fishingAt,
  }) async {
    final isAuthor = spot.userId == requesterUserId;
    if (!isAuthor && !requesterIsAdmin) {
      throw StateError("僅作者或管理員可編輯釣點");
    }

    final updated = FishingSpot(
      id: spot.id,
      lat: lat,
      lng: lng,
      name: name,
      description: description,
      userId: spot.userId,
      photoUrls: spot.photoUrls,
      createdAt: spot.createdAt,
      categoryIds: categoryIds,
      entryKind: spot.entryKind,
      moderationStatus: spot.moderationStatus,
      environmentAtPost: spot.environmentAtPost,
      fishingAt: fishingAt,
      cwaLinkedTideStationId: spot.cwaLinkedTideStationId,
      cwaLinkedTideStationNameZh: spot.cwaLinkedTideStationNameZh,
      cwaLinkedBuoyStationId: spot.cwaLinkedBuoyStationId,
      cwaLinkedBuoyStationNameZh: spot.cwaLinkedBuoyStationNameZh,
      cwaLinkedStationId: spot.cwaLinkedStationId,
      cwaLinkedStationNameZh: spot.cwaLinkedStationNameZh,
    );

    await _db
        .collection("spots")
        .doc(spot.id)
        .update(updated.toFirestoreUpdatePayload())
        .timeout(const Duration(seconds: 20));
    return updated;
  }

  Future<void> deleteSpot({
    required String spotId,
    required String requesterUserId,
    required bool requesterIsAdmin,
  }) async {
    final doc = await _db.collection("spots").doc(spotId).get();
    final data = doc.data();
    if (data == null) return;
    final owner = (data["userId"] as String?) ?? "";
    if (owner != requesterUserId && !requesterIsAdmin) {
      throw StateError("僅作者或管理員可刪除釣點");
    }

    final comments = await _db
        .collection("spots")
        .doc(spotId)
        .collection("comments")
        .get();
    final batch = _db.batch();
    for (final c in comments.docs) {
      batch.delete(c.reference);
    }
    batch.delete(_db.collection("spots").doc(spotId));
    await batch.commit();
  }

  Future<void> deleteComment({
    required String spotId,
    required String commentId,
    required String requesterUserId,
    required bool requesterIsAdmin,
  }) async {
    final ref = _db
        .collection("spots")
        .doc(spotId)
        .collection("comments")
        .doc(commentId);
    final doc = await ref.get();
    final data = doc.data();
    if (data == null) return;
    final owner = (data["userId"] as String?) ?? "";
    if (owner != requesterUserId && !requesterIsAdmin) {
      throw StateError("僅能刪除自己的留言，或由管理員刪除");
    }
    await ref.delete();
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final snap = await _db.collection("spots").get();
    final next = <FishingSpot>[];
    for (final doc in snap.docs) {
      try {
        next.add(FishingSpot.fromDoc(doc));
      } catch (_) {}
    }
    next.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _spots
      ..clear()
      ..addAll(next);
    _loaded = true;
  }
}
