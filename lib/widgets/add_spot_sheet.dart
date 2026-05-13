import "dart:async";
import "dart:typed_data";

import "package:fishing_map/models/fishing_spot.dart";
import "package:fishing_map/models/map_view_settings.dart";
import "package:fishing_map/models/spot_category.dart";
import "package:fishing_map/models/spot_entry_kind.dart";
import "package:fishing_map/models/spot_moderation_status.dart";
import "package:fishing_map/data/cwa_station_loader.dart";
import "package:fishing_map/data/cwa_station_nearest.dart";
import "package:fishing_map/models/cwa_station_kind.dart";
import "package:fishing_map/models/cwa_station_point.dart";
import "package:fishing_map/services/auth_service.dart";
import "package:fishing_map/services/spot_environment_fetch_service.dart";
import "package:fishing_map/services/spot_repository.dart";
import "package:fishing_map/widgets/mapbox_interaction_overlay.dart";
import "package:flutter/material.dart";
import "package:image_picker/image_picker.dart";
import "package:latlong2/latlong.dart";

/// [AddSpotSheet.open] 成功關閉時回傳。
enum AddSpotSheetOutcome {
  /// 釣況分享已上地圖。
  conditionSharePublished,

  /// 固定釣點：待審核。
  fishingPoiSubmittedPending,

  /// 固定釣點：管理員直接核准上地圖。
  fishingPoiPublishedApproved,
}

/// 釣況分享／固定釣點表單字串（對應地圖標籤語言）。
class _AddSpotCopy {
  const _AddSpotCopy(this.lang);
  final MapLabelLanguage lang;

  String sheetTitle(SpotEntryKind kind) {
    if (kind == SpotEntryKind.conditionShare) {
      return switch (lang) {
        MapLabelLanguage.english => "Share fishing conditions",
        MapLabelLanguage.simplifiedChinese => "分享钓况",
        MapLabelLanguage.traditionalChinese => "釣況分享",
      };
    }
    return switch (lang) {
      MapLabelLanguage.english => "Add fishing spot (map POI)",
      MapLabelLanguage.simplifiedChinese => "新增固定钓点",
      MapLabelLanguage.traditionalChinese => "新增固定釣點",
    };
  }

  String coordsLine(String lat, String lng) => switch (lang) {
        MapLabelLanguage.english => "Approx. coordinates: $lat, $lng",
        MapLabelLanguage.simplifiedChinese => "坐标约：$lat, $lng",
        MapLabelLanguage.traditionalChinese => "座標約：$lat, $lng",
      };

  String spotNameLabel(SpotEntryKind kind) {
    if (kind == SpotEntryKind.conditionShare) {
      return switch (lang) {
        MapLabelLanguage.english => "Share title",
        MapLabelLanguage.simplifiedChinese => "分享标题",
        MapLabelLanguage.traditionalChinese => "分享標題",
      };
    }
    return switch (lang) {
      MapLabelLanguage.english => "Spot name",
      MapLabelLanguage.simplifiedChinese => "钓点名称",
      MapLabelLanguage.traditionalChinese => "釣點名稱",
    };
  }

  String get spotTypeTitle => switch (lang) {
        MapLabelLanguage.english => "Venue type",
        MapLabelLanguage.simplifiedChinese => "钓场类型",
        MapLabelLanguage.traditionalChinese => "釣場類型",
      };

  String get saltwater => switch (lang) {
        MapLabelLanguage.english => "Saltwater",
        MapLabelLanguage.simplifiedChinese => "海水",
        MapLabelLanguage.traditionalChinese => "海水",
      };

  String get freshwater => switch (lang) {
        MapLabelLanguage.english => "Freshwater",
        MapLabelLanguage.simplifiedChinese => "淡水",
        MapLabelLanguage.traditionalChinese => "淡水",
      };

  String get descriptionLabel => switch (lang) {
        MapLabelLanguage.english =>
          "Notes (tide, parking, safety…)",
        MapLabelLanguage.simplifiedChinese => "描述（潮汐、车位、安全事项等）",
        MapLabelLanguage.traditionalChinese => "描述（潮汐、車位、注意安全事項⋯）",
      };

  String pickPhotosLabel(int count) => switch (lang) {
        MapLabelLanguage.english => count == 0
            ? "Photos (up to 6)"
            : "$count selected • change",
        MapLabelLanguage.simplifiedChinese =>
          count == 0 ? "选择照片（最多 6 张）" : "已选 $count 张 • 更改",
        MapLabelLanguage.traditionalChinese =>
          count == 0 ? "選擇照片（最多 6 張）" : "已選 $count 張 • 更正",
      };

  String get publish => switch (lang) {
        MapLabelLanguage.english => "Publish",
        MapLabelLanguage.simplifiedChinese => "发布",
        MapLabelLanguage.traditionalChinese => "發布",
      };

  String get publishSubmitReview => switch (lang) {
        MapLabelLanguage.english => "Submit for review",
        MapLabelLanguage.simplifiedChinese => "提交审核",
        MapLabelLanguage.traditionalChinese => "提交審核",
      };

  String get publishAsAdmin => switch (lang) {
        MapLabelLanguage.english => "Publish (skip review)",
        MapLabelLanguage.simplifiedChinese => "直接发布（管理员）",
        MapLabelLanguage.traditionalChinese => "立即發布（管理員）",
      };

  String get moderationHintPoiMember => switch (lang) {
        MapLabelLanguage.english =>
          "This map POI stays hidden until an admin approves it.",
        MapLabelLanguage.simplifiedChinese =>
          "固定钓点需管理员审核通过后才会显示在地图上。",
        MapLabelLanguage.traditionalChinese =>
          "固定釣點須經管理員審核通過後，才會顯示於公開地圖。",
      };

  String get errLogin => switch (lang) {
        MapLabelLanguage.english => "Please sign in first",
        MapLabelLanguage.simplifiedChinese => "请先登录",
        MapLabelLanguage.traditionalChinese => "請先登入",
      };

  String errName(SpotEntryKind kind) {
    if (kind == SpotEntryKind.conditionShare) {
      return switch (lang) {
        MapLabelLanguage.english => "Enter a title",
        MapLabelLanguage.simplifiedChinese => "请输入标题",
        MapLabelLanguage.traditionalChinese => "請輸入標題",
      };
    }
    return switch (lang) {
      MapLabelLanguage.english => "Enter a spot name",
      MapLabelLanguage.simplifiedChinese => "请输入钓点名称",
      MapLabelLanguage.traditionalChinese => "請輸入釣點名稱",
    };
  }

  String statusCreating(SpotEntryKind kind) {
    if (kind == SpotEntryKind.conditionShare) {
      return switch (lang) {
        MapLabelLanguage.english => "Publishing…",
        MapLabelLanguage.simplifiedChinese => "正在发布…",
        MapLabelLanguage.traditionalChinese => "正在發布分享...",
      };
    }
    return switch (lang) {
      MapLabelLanguage.english => "Creating spot…",
      MapLabelLanguage.simplifiedChinese => "正在建立钓点…",
      MapLabelLanguage.traditionalChinese => "正在建立固定釣點...",
    };
  }

  String statusUploading(int i, int n) => switch (lang) {
        MapLabelLanguage.english => "Uploading photo $i/$n…",
        MapLabelLanguage.simplifiedChinese => "正在上传照片 $i/$n…",
        MapLabelLanguage.traditionalChinese => "正在上傳照片 $i/$n...",
      };

  String get statusSavingPhotos => switch (lang) {
        MapLabelLanguage.english => "Saving photo links…",
        MapLabelLanguage.simplifiedChinese => "正在保存照片链接…",
        MapLabelLanguage.traditionalChinese => "正在儲存照片連結...",
      };

  String get statusWeather => switch (lang) {
        MapLabelLanguage.english => "Fetching CWA trip weather…",
        MapLabelLanguage.simplifiedChinese => "正在从气象局获取出钓时段气象…",
        MapLabelLanguage.traditionalChinese => "擷取出釣時段氣象（中央氣象署）…",
      };

  String get errTimeout => switch (lang) {
        MapLabelLanguage.english =>
          "Timed out. Check your network or Firebase rules and try again.",
        MapLabelLanguage.simplifiedChinese =>
          "新增超时，请检查网络或 Firebase 规则后再试。",
        MapLabelLanguage.traditionalChinese =>
          "新增逾時，請檢查網路或 Firebase 規則後再試一次。",
      };
}

class AddSpotSheet extends StatefulWidget {
  const AddSpotSheet({
    super.key,
    required this.pick,
    required this.repo,
    required this.auth,
    required this.mapLanguage,
    required this.entryKind,
  });

  final LatLng pick;
  final SpotRepository repo;
  final AuthService auth;
  final MapLabelLanguage mapLanguage;
  final SpotEntryKind entryKind;

  static Future<AddSpotSheetOutcome?> open(
    BuildContext context, {
    required LatLng pick,
    required SpotRepository repo,
    required AuthService auth,
    required MapLabelLanguage mapLanguage,
    required SpotEntryKind entryKind,
  }) {
    pushMapboxInteractionBlock();
    return showModalBottomSheet<AddSpotSheetOutcome>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(ctx).bottom),
        child: AddSpotSheet(
          pick: pick,
          repo: repo,
          auth: auth,
          mapLanguage: mapLanguage,
          entryKind: entryKind,
        ),
      ),
    ).whenComplete(popMapboxInteractionBlock);
  }

  @override
  State<AddSpotSheet> createState() => _AddSpotSheetState();
}

class _AddSpotSheetState extends State<AddSpotSheet> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _picker = ImagePicker();
  bool _busy = false;
  String? _error;
  String? _status;
  final List<({Uint8List bytes, String mime})> _images = [];
  final Set<String> _selectedCategoryIds = {kDefaultSpotCategoryId};
  bool _isAdmin = false;
  bool _adminResolved = false;

  _AddSpotCopy get _txt => _AddSpotCopy(widget.mapLanguage);

  @override
  void initState() {
    super.initState();
    if (widget.entryKind == SpotEntryKind.fishingPoi) {
      unawaited(_resolveAdmin());
    } else {
      _adminResolved = true;
      _isAdmin = false;
    }
  }

  Future<void> _resolveAdmin() async {
    final v = await widget.auth.isCurrentUserAdmin();
    if (!mounted) return;
    setState(() {
      _isAdmin = v;
      _adminResolved = true;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final pics = await _picker.pickMultiImage(
      imageQuality: 88,
      maxWidth: 1600,
    );
    if (pics.isEmpty) return;
    final next = <({Uint8List bytes, String mime})>[..._images];
    for (final p in pics) {
      final mime = p.mimeType ?? "image/jpeg";
      next.add((bytes: await p.readAsBytes(), mime: mime));
    }
    setState(() {
      _images
        ..clear()
        ..addAll(next.take(6));
    });
  }

  /// 關閉表單後於背景擷取／寫入海象；避免 CWA 逾時或載入 StationID.json 卡住「發布」。
  Future<void> _syncEnvironmentAfterCreate({
    required SpotRepository repo,
    required String spotId,
    required double lat,
    required double lng,
    required DateTime when,
  }) async {
    try {
      CwaStationPoint? tidePt;
      CwaStationPoint? buoyPt;
      try {
        final stations = await loadCwaStationPointsFromAsset();
        tidePt = findNearestCwaStationOfKind(
          lat,
          lng,
          stations,
          CwaStationKind.tide,
        );
        buoyPt = findNearestCwaStationOfKind(
          lat,
          lng,
          stations,
          CwaStationKind.buoy,
        );
      } catch (_) {
        // 無資產或解析失敗時 API 端仍可能以座標選站
      }
      await repo.setCwaTideBuoyStationLinks(
        spotId,
        tideStationId: tidePt?.id,
        tideStationNameZh: tidePt?.name,
        buoyStationId: buoyPt?.id,
        buoyStationNameZh: buoyPt?.name,
      );
      final env = await SpotEnvironmentFetchService()
          .fetchMergedTideBuoyForInstant(
            lat: lat,
            lng: lng,
            when: when,
            tideStationId: tidePt?.id,
            buoyStationId: buoyPt?.id,
          )
          .timeout(const Duration(seconds: 50));
      await repo.setEnvironmentAtPost(spotId, env);
    } catch (_) {
      // 背景擷取失敗僅略過；釣點已建立。
    }
  }

  void _toggleCategory(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedCategoryIds.add(id);
      } else {
        _selectedCategoryIds.remove(id);
        if (_selectedCategoryIds.isEmpty) {
          _selectedCategoryIds.add(kDefaultSpotCategoryId);
        }
      }
    });
  }

  Future<void> _submit() async {
    final t = _txt;
    final u = widget.auth.currentUser;
    if (u == null) {
      setState(() => _error = t.errLogin);
      return;
    }
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = t.errName(widget.entryKind));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = t.statusCreating(widget.entryKind);
    });

    try {
      final isAdmin = await widget.auth.isCurrentUserAdmin();
      final kind = widget.entryKind;
      final SpotModerationStatus mod = kind == SpotEntryKind.conditionShare
          ? SpotModerationStatus.approved
          : (isAdmin
              ? SpotModerationStatus.approved
              : SpotModerationStatus.pending);
      final draft = FishingSpot(
        id: "",
        lat: widget.pick.latitude,
        lng: widget.pick.longitude,
        name: name,
        description: _desc.text.trim(),
        userId: u.uid,
        photoUrls: const [],
        createdAt: DateTime.now(),
        categoryIds: normalizeCategoryIds(_selectedCategoryIds),
        entryKind: kind,
        moderationStatus: mod,
      );
      final id = await widget.repo
          .createDraftSpot(
            draft: draft,
            userId: u.uid,
            entryKind: kind,
            moderationStatus: mod,
          )
          .timeout(const Duration(seconds: 20));
      final urls = <String>[];
      for (var i = 0; i < _images.length; i++) {
        final img = _images[i];
        if (mounted) {
          setState(
              () => _status = t.statusUploading(i + 1, _images.length));
        }
        final url = await widget.repo
            .uploadSpotPhoto(spotId: id, bytes: img.bytes, mime: img.mime)
            .timeout(const Duration(seconds: 30));
        urls.add(url);
      }
      if (mounted) setState(() => _status = t.statusSavingPhotos);
      await widget.repo
          .attachPhotoUrls(id, urls)
          .timeout(const Duration(seconds: 20));

      final spotId = id;
      final lat = widget.pick.latitude;
      final lng = widget.pick.longitude;
      final when = DateTime.now();
      final repo = widget.repo;

      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
      });
      final AddSpotSheetOutcome outcome = kind == SpotEntryKind.conditionShare
          ? AddSpotSheetOutcome.conditionSharePublished
          : (isAdmin
              ? AddSpotSheetOutcome.fishingPoiPublishedApproved
              : AddSpotSheetOutcome.fishingPoiSubmittedPending);
      Navigator.of(context).pop(outcome);
      unawaited(
        _syncEnvironmentAfterCreate(
          repo: repo,
          spotId: spotId,
          lat: lat,
          lng: lng,
          when: when,
        ),
      );
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
          _error = t.errTimeout;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = _txt;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: bottomInset + 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.sheetTitle(widget.entryKind),
            style:
                theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            t.coordsLine(
              widget.pick.latitude.toStringAsFixed(4),
              widget.pick.longitude.toStringAsFixed(4),
            ),
            style: theme.textTheme.bodySmall,
          ),
          if (_adminResolved &&
              !_isAdmin &&
              widget.entryKind == SpotEntryKind.fishingPoi) ...[
            const SizedBox(height: 8),
            Text(
              t.moderationHintPoiMember,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: t.spotNameLabel(widget.entryKind),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text(t.spotTypeTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            "可複選",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(t.saltwater, style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o
                  in kSpotCategoryOptions.where((e) => e.id.startsWith("1-")))
                FilterChip(
                  label: Text(o.sublabel),
                  selected: _selectedCategoryIds.contains(o.id),
                  onSelected: _busy
                      ? null
                      : (v) => _toggleCategory(o.id, v),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(t.freshwater, style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o
                  in kSpotCategoryOptions.where((e) => e.id.startsWith("2-")))
                FilterChip(
                  label: Text(o.sublabel),
                  selected: _selectedCategoryIds.contains(o.id),
                  onSelected: _busy
                      ? null
                      : (v) => _toggleCategory(o.id, v),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: t.descriptionLabel,
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickPhotos,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(t.pickPhotosLabel(_images.length)),
          ),
          if (_images.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Image.memory(
                        _images[i].bytes,
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (_busy && _status != null) ...[
            const SizedBox(height: 10),
            Text(_status!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    widget.entryKind == SpotEntryKind.conditionShare
                        ? t.publish
                        : (_adminResolved
                            ? (_isAdmin
                                ? t.publishAsAdmin
                                : t.publishSubmitReview)
                            : t.publishSubmitReview),
                  ),
          ),
        ],
      ),
    );
  }
}
