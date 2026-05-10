import "dart:async";
import "dart:typed_data";

import "package:fishing_map/models/fishing_spot.dart";
import "package:fishing_map/models/map_view_settings.dart";
import "package:fishing_map/models/spot_category.dart";
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

/// 新增釣點表單字串（對應地圖標籤語言）。
class _AddSpotCopy {
  const _AddSpotCopy(this.lang);
  final MapLabelLanguage lang;

  String get sheetTitle => switch (lang) {
        MapLabelLanguage.english => "Add fishing spot",
        MapLabelLanguage.simplifiedChinese => "新增钓点",
        MapLabelLanguage.traditionalChinese => "新增釣點",
      };

  String coordsLine(String lat, String lng) => switch (lang) {
        MapLabelLanguage.english => "Approx. coordinates: $lat, $lng",
        MapLabelLanguage.simplifiedChinese => "坐标约：$lat, $lng",
        MapLabelLanguage.traditionalChinese => "座標約：$lat, $lng",
      };

  String get outingTitle => switch (lang) {
        MapLabelLanguage.english => "Trip date & time",
        MapLabelLanguage.simplifiedChinese => "出钓日期与时间",
        MapLabelLanguage.traditionalChinese => "出釣日期與時間",
      };

  String get outingHint => switch (lang) {
        MapLabelLanguage.english =>
          "Sea-state prefers CWA O-B0075-002 (falls back to 001) at this moment when authorized and inside Taiwan bounds.",
        MapLabelLanguage.simplifiedChinese =>
          "海象快照依此时间，优先中央气象局 O-B0075-002、必要时 001（须授权且坐标在台澎金马范围内）。",
        MapLabelLanguage.traditionalChinese =>
          "海象快照會依此時間，優先中央氣象署 O-B0075-002、必要時改採 001（須授權且座標在臺澎金馬範圍內）。",
      };

  String get spotNameLabel => switch (lang) {
        MapLabelLanguage.english => "Spot name",
        MapLabelLanguage.simplifiedChinese => "钓点名称",
        MapLabelLanguage.traditionalChinese => "釣點名稱",
      };

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

  String get errLogin => switch (lang) {
        MapLabelLanguage.english => "Please sign in first",
        MapLabelLanguage.simplifiedChinese => "请先登录",
        MapLabelLanguage.traditionalChinese => "請先登入",
      };

  String get errName => switch (lang) {
        MapLabelLanguage.english => "Enter a spot name",
        MapLabelLanguage.simplifiedChinese => "请输入钓点名称",
        MapLabelLanguage.traditionalChinese => "請輸入釣點名稱",
      };

  String get statusCreating => switch (lang) {
        MapLabelLanguage.english => "Creating spot…",
        MapLabelLanguage.simplifiedChinese => "正在建立钓点…",
        MapLabelLanguage.traditionalChinese => "正在建立釣點...",
      };

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

String _formatOutingButtonLabel(DateTime d, MapLabelLanguage lang) {
  final x = d.toLocal();
  switch (lang) {
    case MapLabelLanguage.english:
      const mon = [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec",
      ];
      final h = x.hour.toString().padLeft(2, "0");
      final m = x.minute.toString().padLeft(2, "0");
      return "${mon[x.month - 1]} ${x.day}, ${x.year}, $h:$m";
    case MapLabelLanguage.simplifiedChinese:
    case MapLabelLanguage.traditionalChinese:
      return "${x.year}/${x.month}/${x.day} "
          "${x.hour.toString().padLeft(2, "0")}:"
          "${x.minute.toString().padLeft(2, "0")}";
  }
}

class AddSpotSheet extends StatefulWidget {
  const AddSpotSheet({
    super.key,
    required this.pick,
    required this.repo,
    required this.auth,
    required this.mapLanguage,
  });

  final LatLng pick;
  final SpotRepository repo;
  final AuthService auth;
  final MapLabelLanguage mapLanguage;

  static Future<bool?> open(
    BuildContext context, {
    required LatLng pick,
    required SpotRepository repo,
    required AuthService auth,
    required MapLabelLanguage mapLanguage,
  }) {
    pushMapboxInteractionBlock();
    return showModalBottomSheet<bool>(
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
  String _categoryId = kDefaultSpotCategoryId;

  /// 使用者填寫的出釣日時；氣象快照依此時段擷取。
  DateTime _fishingAt = DateTime.now();

  _AddSpotCopy get _txt => _AddSpotCopy(widget.mapLanguage);

  Locale get _locale => widget.mapLanguage.materialLocale;

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

  Future<void> _pickFishingWhen() async {
    if (_busy) return;
    final first = DateTime(2020, 1, 1);
    final last = DateTime.now().add(const Duration(days: 400));
    DateTime clamp(DateTime x) {
      if (x.isBefore(first)) return first;
      if (x.isAfter(last)) return last;
      return x;
    }

    final d = await showDatePicker(
      context: context,
      locale: _locale,
      initialDate: clamp(_fishingAt),
      firstDate: first,
      lastDate: last,
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_fishingAt),
      builder: (ctx, child) => Localizations.override(
        context: ctx,
        locale: _locale,
        child: child!,
      ),
    );
    if (t == null || !mounted) return;
    setState(() {
      _fishingAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
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
      setState(() => _error = t.errName);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = t.statusCreating;
    });

    try {
      final draft = FishingSpot(
        id: "",
        lat: widget.pick.latitude,
        lng: widget.pick.longitude,
        name: name,
        description: _desc.text.trim(),
        userId: u.uid,
        photoUrls: const [],
        createdAt: DateTime.now(),
        categoryId: _categoryId,
        fishingAt: _fishingAt,
      );
      final id = await widget.repo
          .createDraftSpot(draft: draft, userId: u.uid)
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
      final when = _fishingAt;
      final repo = widget.repo;

      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
      });
      Navigator.of(context).pop(true);
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
            t.sheetTitle,
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
          const SizedBox(height: 16),
          Text(t.outingTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFishingWhen,
            icon: const Icon(Icons.event_outlined, size: 20),
            label: Text(
              _formatOutingButtonLabel(_fishingAt, widget.mapLanguage),
            ),
          ),
          Text(
            t.outingHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: t.spotNameLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text(t.spotTypeTitle, style: theme.textTheme.titleSmall),
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
                  selected: _categoryId == o.id,
                  onSelected: _busy
                      ? null
                      : (v) {
                          if (v) setState(() => _categoryId = o.id);
                        },
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
                  selected: _categoryId == o.id,
                  onSelected: _busy
                      ? null
                      : (v) {
                          if (v) setState(() => _categoryId = o.id);
                        },
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
                : Text(t.publish),
          ),
        ],
      ),
    );
  }
}
