import "dart:async";
import "dart:typed_data";

import "package:fishing_map/models/fishing_spot.dart";
import "package:fishing_map/models/map_view_settings.dart";
import "package:fishing_map/models/spot_category.dart";
import "package:fishing_map/services/auth_service.dart";
import "package:fishing_map/services/spot_repository.dart";
import "package:fishing_map/widgets/mapbox_interaction_overlay.dart";
import "package:flutter/material.dart";
import "package:image_picker/image_picker.dart";

class _EditSpotCopy {
  const _EditSpotCopy(this.lang);
  final MapLabelLanguage lang;

  String get sheetTitle => switch (lang) {
        MapLabelLanguage.english => "Edit fishing spot",
        MapLabelLanguage.simplifiedChinese => "编辑钓点",
        MapLabelLanguage.traditionalChinese => "編輯釣點",
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

  String get latLabel => switch (lang) {
        MapLabelLanguage.english => "Latitude (WGS84)",
        MapLabelLanguage.simplifiedChinese => "纬度 (WGS84)",
        MapLabelLanguage.traditionalChinese => "緯度 (WGS84)",
      };

  String get lngLabel => switch (lang) {
        MapLabelLanguage.english => "Longitude (WGS84)",
        MapLabelLanguage.simplifiedChinese => "经度 (WGS84)",
        MapLabelLanguage.traditionalChinese => "經度 (WGS84)",
      };

  String pickPhotosLabel(int existing, int newCount, int remaining) => switch (lang) {
        MapLabelLanguage.english =>
          newCount == 0 ? "Add photos (up to $remaining more)" : "$newCount new • ${existing + newCount}/${existing + remaining} slots",
        MapLabelLanguage.simplifiedChinese =>
          newCount == 0 ? "添加照片（还可 $remaining 张）" : "新增 $newCount 张 • 共 ${existing + newCount}",
        MapLabelLanguage.traditionalChinese =>
          newCount == 0 ? "新增照片（還可加 $remaining 張）" : "新增 $newCount 張 • 共 ${existing + newCount} 張",
      };

  String get save => switch (lang) {
        MapLabelLanguage.english => "Save",
        MapLabelLanguage.simplifiedChinese => "保存",
        MapLabelLanguage.traditionalChinese => "儲存",
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

  String get errCoords => switch (lang) {
        MapLabelLanguage.english => "Enter valid latitude and longitude",
        MapLabelLanguage.simplifiedChinese => "请输入有效的经纬度",
        MapLabelLanguage.traditionalChinese => "請輸入有效的經緯度",
      };

  String statusSaving(int phase, int phases) => switch (lang) {
        MapLabelLanguage.english => "Saving… ($phase/$phases)",
        MapLabelLanguage.simplifiedChinese => "正在保存… ($phase/$phases)",
        MapLabelLanguage.traditionalChinese => "正在儲存… ($phase/$phases)",
      };

  String get errTimeout => switch (lang) {
        MapLabelLanguage.english =>
          "Timed out. Check your network or Firebase rules.",
        MapLabelLanguage.simplifiedChinese => "超时，请检查网络或 Firebase 规则。",
        MapLabelLanguage.traditionalChinese => "逾時，請檢查網路或 Firebase 規則。",
      };
}

class EditSpotSheet extends StatefulWidget {
  const EditSpotSheet({
    super.key,
    required this.spot,
    required this.repo,
    required this.auth,
    required this.mapLanguage,
  });

  final FishingSpot spot;
  final SpotRepository repo;
  final AuthService auth;
  final MapLabelLanguage mapLanguage;

  /// 完成後傳回更新後的 [FishingSpot]，取消為 null。
  static Future<FishingSpot?> open(
    BuildContext context, {
    required FishingSpot spot,
    required SpotRepository repo,
    required AuthService auth,
    required MapLabelLanguage mapLanguage,
  }) {
    pushMapboxInteractionBlock();
    return showModalBottomSheet<FishingSpot?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(ctx).bottom),
        child: EditSpotSheet(
          spot: spot,
          repo: repo,
          auth: auth,
          mapLanguage: mapLanguage,
        ),
      ),
    ).whenComplete(popMapboxInteractionBlock);
  }

  @override
  State<EditSpotSheet> createState() => _EditSpotSheetState();
}

class _EditSpotSheetState extends State<EditSpotSheet> {
  static const int _kMaxPhotosPerSpot = 6;

  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  final _picker = ImagePicker();
  bool _busy = false;
  String? _error;
  String? _status;
  late final Set<String> _selectedCategoryIds;
  final List<({Uint8List bytes, String mime})> _newImages = [];

  _EditSpotCopy get _txt => _EditSpotCopy(widget.mapLanguage);

  @override
  void initState() {
    super.initState();
    final s = widget.spot;
    _name = TextEditingController(text: s.name);
    _desc = TextEditingController(text: s.description);
    _lat = TextEditingController(text: s.lat.toStringAsFixed(6));
    _lng = TextEditingController(text: s.lng.toStringAsFixed(6));
    _selectedCategoryIds = Set<String>.from(s.categoryIds);
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  int get _remainingPhotoSlots =>
      (_kMaxPhotosPerSpot - widget.spot.photoUrls.length).clamp(0, _kMaxPhotosPerSpot);

  Future<void> _pickPhotos() async {
    if (_busy) return;
    final pics = await _picker.pickMultiImage(
      imageQuality: 88,
      maxWidth: 1600,
    );
    if (pics.isEmpty) return;
    final appended = <({Uint8List bytes, String mime})>[..._newImages];
    for (final p in pics) {
      if (widget.spot.photoUrls.length + appended.length >= _kMaxPhotosPerSpot) {
        break;
      }
      final mime = p.mimeType ?? "image/jpeg";
      appended.add((bytes: await p.readAsBytes(), mime: mime));
    }
    setState(() {
      _newImages
        ..clear()
        ..addAll(appended);
    });
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
      setState(() => _error = t.errName);
      return;
    }
    final lat = double.tryParse(_lat.text.trim().replaceAll(",", "."));
    final lng = double.tryParse(_lng.text.trim().replaceAll(",", "."));
    if (lat == null || lng == null || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      setState(() => _error = t.errCoords);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _status = t.statusSaving(1, _newImages.isEmpty ? 1 : 2);
    });

    try {
      final isAdmin = await widget.auth.isCurrentUserAdmin();
      var updated = await widget.repo
          .updateSpot(
            spot: widget.spot,
            requesterUserId: u.uid,
            requesterIsAdmin: isAdmin,
            name: name,
            description: _desc.text.trim(),
            categoryIds: normalizeCategoryIds(_selectedCategoryIds),
            lat: lat,
            lng: lng,
            fishingAt: null,
          )
          .timeout(const Duration(seconds: 25));

      if (_newImages.isNotEmpty && mounted) {
        setState(() => _status = t.statusSaving(2, 2));
        final urls = <String>[];
        for (var i = 0; i < _newImages.length; i++) {
          final img = _newImages[i];
          final url = await widget.repo
              .uploadSpotPhoto(
                spotId: updated.id,
                bytes: img.bytes,
                mime: img.mime,
              )
              .timeout(const Duration(seconds: 30));
          urls.add(url);
        }
        await widget.repo
            .attachPhotoUrls(updated.id, urls)
            .timeout(const Duration(seconds: 20));
        updated = FishingSpot(
          id: updated.id,
          lat: updated.lat,
          lng: updated.lng,
          name: updated.name,
          description: updated.description,
          userId: updated.userId,
          photoUrls: [...updated.photoUrls, ...urls],
          createdAt: updated.createdAt,
          categoryIds: updated.categoryIds,
          entryKind: updated.entryKind,
          moderationStatus: updated.moderationStatus,
          environmentAtPost: updated.environmentAtPost,
          fishingAt: updated.fishingAt,
          cwaLinkedTideStationId: updated.cwaLinkedTideStationId,
          cwaLinkedTideStationNameZh: updated.cwaLinkedTideStationNameZh,
          cwaLinkedBuoyStationId: updated.cwaLinkedBuoyStationId,
          cwaLinkedBuoyStationNameZh: updated.cwaLinkedBuoyStationNameZh,
          cwaLinkedStationId: updated.cwaLinkedStationId,
          cwaLinkedStationNameZh: updated.cwaLinkedStationNameZh,
        );
      }

      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
      });
      Navigator.of(context).pop(updated);
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
    final remaining = _remainingPhotoSlots;
    final newCount = _newImages.length;

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
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: t.spotNameLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _lat,
            decoration: InputDecoration(
              labelText: t.latLabel,
              border: const OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _lng,
            decoration: InputDecoration(
              labelText: t.lngLabel,
              border: const OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
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
          if (remaining > 0) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickPhotos,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                t.pickPhotosLabel(widget.spot.photoUrls.length, newCount, remaining),
              ),
            ),
            if (newCount > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: newCount,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Image.memory(
                          _newImages[i].bytes,
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
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
                : Text(t.save),
          ),
        ],
      ),
    );
  }
}
