import "package:fishing_map/config/map_tokens.dart";
import "package:fishing_map/models/fishing_spot.dart";
import "package:fishing_map/models/spot_environment_snapshot.dart";
import "package:fishing_map/services/spot_environment_fetch_service.dart";
import "package:flutter/material.dart";

String? _formatInstantLocal(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final loc = d.toLocal();
  return "${loc.year}/${loc.month}/${loc.day} "
      "${loc.hour.toString().padLeft(2, '0')}:"
      "${loc.minute.toString().padLeft(2, '0')}";
}

String _formatDateTimeLocal(DateTime d) {
  final loc = d.toLocal();
  return "${loc.year}/${loc.month}/${loc.day} "
      "${loc.hour.toString().padLeft(2, '0')}:"
      "${loc.minute.toString().padLeft(2, '0')}";
}

String? _linkedSummary(FishingSpot s) {
  final tid = s.cwaLinkedTideStationId ?? s.cwaLinkedStationId;
  final tname = s.cwaLinkedTideStationNameZh ?? s.cwaLinkedStationNameZh;
  final bid = s.cwaLinkedBuoyStationId;
  final bname = s.cwaLinkedBuoyStationNameZh;
  final lines = <String>[];
  if (tid != null && tid.isNotEmpty) {
    lines.add(
      "潮位站：$tid${tname != null && tname.isNotEmpty ? " · $tname" : ""}",
    );
  }
  if (bid != null && bid.isNotEmpty) {
    lines.add(
      "浮標站：$bid${bname != null && bname.isNotEmpty ? " · $bname" : ""}",
    );
  }
  if (lines.isEmpty) return null;
  return lines.join("\n");
}

/// 顯示已儲存的氣象快照，或舊資料以出針時間／建立時間回溯（無查詢 UI）。
class SpotEnvironmentCard extends StatefulWidget {
  const SpotEnvironmentCard({super.key, required this.spot});

  final FishingSpot spot;

  @override
  State<SpotEnvironmentCard> createState() => _SpotEnvironmentCardState();
}

class _SpotEnvironmentCardState extends State<SpotEnvironmentCard> {
  final _svc = SpotEnvironmentFetchService();
  Future<SpotEnvironmentSnapshot>? _legacyFuture;

  @override
  void initState() {
    super.initState();
    _scheduleLegacy();
  }

  @override
  void didUpdateWidget(covariant SpotEnvironmentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spot.id != widget.spot.id) {
      _scheduleLegacy();
    }
  }

  void _scheduleLegacy() {
    if (widget.spot.environmentAtPost != null) {
      _legacyFuture = null;
      return;
    }
    final when = widget.spot.fishingAt ?? widget.spot.createdAt;
    final tid = (widget.spot.cwaLinkedTideStationId ?? widget.spot.cwaLinkedStationId)
        ?.trim();
    final bid = widget.spot.cwaLinkedBuoyStationId?.trim();
    if (tid != null &&
        tid.isNotEmpty &&
        bid != null &&
        bid.isNotEmpty) {
      _legacyFuture = _svc.fetchMergedTideBuoyForInstant(
        lat: widget.spot.lat,
        lng: widget.spot.lng,
        when: when,
        tideStationId: tid,
        buoyStationId: bid,
      );
    } else {
      final single = (tid != null && tid.isNotEmpty)
          ? tid
          : (bid != null && bid.isNotEmpty ? bid : null);
      _legacyFuture = _svc.fetchForInstant(
        lat: widget.spot.lat,
        lng: widget.spot.lng,
        when: when,
        linkedCwaStationId: single,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stored = widget.spot.environmentAtPost;

    if (stored != null) {
      if (stored.cardTideBuoySplit) {
        return _buildTideBuoySplitCard(
          theme,
          stored,
          fishingAt: widget.spot.fishingAt,
          linkedStationSummary: _linkedSummary(widget.spot),
        );
      }
      return _buildCard(
        theme,
        title: "釣況紀錄（出釣時段）",
        e: stored,
        rainHint: "小時雨量（出釣時段附近）",
        fishingAt: widget.spot.fishingAt,
        linkedStationSummary: _linkedSummary(widget.spot),
      );
    }

    return FutureBuilder<SpotEnvironmentSnapshot>(
      future: _legacyFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "此釣點尚無儲存快照；正以「出釣／建立時間」回溯 O-B0075-002／001 海面觀測…",
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (snap.hasError || !snap.hasData) {
          return Text(
            "無法載入氣象資料",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          );
        }
        final e = snap.data!;
        if (e.cardTideBuoySplit) {
          return _buildTideBuoySplitCard(
            theme,
            e,
            fishingAt: widget.spot.fishingAt,
            linkedStationSummary: _linkedSummary(widget.spot),
          );
        }
        return _buildCard(
          theme,
          title: "釣況（舊資料回溯）",
          e: e,
          rainHint: "雨量",
          fishingAt: widget.spot.fishingAt,
          linkedStationSummary: _linkedSummary(widget.spot),
        );
      },
    );
  }

  /// 新增釣點合併擷取：僅潮位站（氣溫、潮位、潮汐、風級）＋浮標（浪高、海溫）。
  Widget _buildTideBuoySplitCard(
    ThemeData theme,
    SpotEnvironmentSnapshot e, {
    DateTime? fishingAt,
    String? linkedStationSummary,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("釣況紀錄（出釣時段）", style: theme.textTheme.titleSmall),
            if (fishingAt != null) ...[
              const SizedBox(height: 4),
              Text(
                "出釣時間：${_formatDateTimeLocal(fishingAt)}（本地）",
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
            if (linkedStationSummary != null) ...[
              const SizedBox(height: 8),
              Text(
                linkedStationSummary,
                style: theme.textTheme.labelMedium?.copyWith(height: 1.35),
              ),
            ],
            if (e.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                e.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (e.tempC != null)
              _kv(theme, "氣溫", "${e.tempC!.toStringAsFixed(1)}°C"),
            if (e.tideHeightM != null)
              _kv(theme, "潮位", "${e.tideHeightM!.toStringAsFixed(2)} m"),
            if (e.tideLevelZh != null && e.tideLevelZh!.isNotEmpty)
              _kv(theme, "潮汐", e.tideLevelZh!),
            if (e.windScaleZh != null && e.windScaleZh!.isNotEmpty)
              _kv(theme, "風級", e.windScaleZh!),
            if (e.waveHeightM != null)
              _kv(theme, "浪高", "${e.waveHeightM!.toStringAsFixed(2)} m"),
            if (e.seaSurfaceTempC != null)
              _kv(theme, "海溫", "${e.seaSurfaceTempC!.toStringAsFixed(1)}°C"),
            if (e.dataSourceNoteZh != null && e.dataSourceNoteZh!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                e.dataSourceNoteZh!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              SpotEnvironmentSnapshot.attribution,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
    ThemeData theme, {
    required String title,
    required SpotEnvironmentSnapshot e,
    required String rainHint,
    DateTime? fishingAt,
    String? linkedStationSummary,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _compileTimeKeyBanner(theme),
            Text(title, style: theme.textTheme.titleSmall),
            if (fishingAt != null) ...[
              const SizedBox(height: 4),
              Text(
                "出釣時間：${_formatDateTimeLocal(fishingAt)}（本地）",
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
            if (linkedStationSummary != null) ...[
              const SizedBox(height: 8),
              _kv(theme, "釣點綁定觀測站", linkedStationSummary),
            ],
            if (e.dataSourceNoteZh != null) ...[
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.85,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Text(
                    e.dataSourceNoteZh!,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ],
            if (_formatInstantLocal(e.representsInstantIso) != null) ...[
              const SizedBox(height: 2),
              Text(
                "資料對應：${_formatInstantLocal(e.representsInstantIso)}（本地）",
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (e.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  e.errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            if (e.cwaStationId != null ||
                e.cwaStationNameZh != null) ...[
              _kv(
                theme,
                "測站",
                [
                  if (e.cwaStationId != null) e.cwaStationId,
                  if (e.cwaStationNameZh != null) e.cwaStationNameZh,
                ].whereType<String>().join(" · "),
              ),
            ],
            if (e.obsDataTimeIso != null)
              _kv(
                theme,
                "觀測時間",
                _formatInstantLocal(e.obsDataTimeIso) ?? e.obsDataTimeIso!,
              ),
            if (e.tempC != null)
              _kv(theme, "氣溫", "${e.tempC!.toStringAsFixed(1)}°C"),
            if (e.weatherLabelZh != null)
              _kv(theme, "天氣", e.weatherLabelZh!),
            if (e.humidityPct != null)
              _kv(theme, "濕度", "${e.humidityPct!.round()}%"),
            if (e.tideHeightM != null ||
                (e.tideLevelZh != null && e.tideLevelZh!.isNotEmpty)) ...[
              if (e.tideHeightM != null)
                _kv(
                  theme,
                  "潮位",
                  "${e.tideHeightM!.toStringAsFixed(2)} m",
                ),
              if (e.tideLevelZh != null && e.tideLevelZh!.isNotEmpty)
                _kv(theme, "潮汐", e.tideLevelZh!),
            ],
            _kv(
              theme,
              "風",
              _formatWindBlock(e),
            ),
            _kv(
              theme,
              rainHint,
              e.precipitationMm != null
                  ? "${e.precipitationMm!.toStringAsFixed(1)} mm"
                  : "—（本資料集未提供）",
            ),
            if (e.marineAvailable) ...[
              _kv(theme, "浪高", _formatWaveHeightLine(e)),
              if (e.waveDirectionDescriptionZh != null &&
                  e.waveDirectionDescriptionZh!.isNotEmpty)
                _kv(theme, "浪向說明", e.waveDirectionDescriptionZh!),
              if (e.wavePeriodS != null)
                _kv(theme, "浪週期", "${e.wavePeriodS!.toStringAsFixed(1)} 秒"),
              if (e.seaSurfaceTempC != null)
                _kv(
                  theme,
                  "海溫",
                  "${e.seaSurfaceTempC!.toStringAsFixed(1)}°C",
                ),
            ] else
              Text(
                "本時段無海面觀測或測站未涵蓋。",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (e.stationPressureHpa != null)
              _kv(
                theme,
                "氣壓",
                "${e.stationPressureHpa!.toStringAsFixed(1)} hPa",
              ),
            if (e.currentDirectionZh != null ||
                e.currentDirectionDescriptionZh != null ||
                e.currentSpeedLabel != null ||
                e.currentSpeedKnotsLabel != null)
              _kv(theme, "海流", _formatCurrentBlock(e)),
            if (e.layerNumber != null)
              _kv(theme, "層次", "${e.layerNumber}"),
            const Divider(height: 20),
            _kv(theme, "月相（參考）", e.moonPhaseZh),
            if (e.tideNoteZh != null) ...[
              const SizedBox(height: 6),
              Text(
                e.tideNoteZh!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              SpotEnvironmentSnapshot.attribution,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 僅反映**本次編譯**是否帶入 `CWA_AUTHORIZATION`（與快照儲存當下是否成功呼叫 API 無直接關係）。
  Widget _compileTimeKeyBanner(ThemeData theme) {
    final ok = cwaAuthorization.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: ok
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                ok ? Icons.verified_outlined : Icons.key_off_outlined,
                size: 20,
                color: ok
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ok
                      ? "本執行檔已帶入 CWA_AUTHORIZATION，可呼叫中央氣象署 Open Data"
                          "（優先海象 O-B0075-002，必要時 001）。是否成功套用請看下方「資料來源」。"
                      : "密鑰寫在 dart_defines.json 仍會顯示此訊息：CWA 授權是在「編譯／啟動」時才讀入，"
                          "改 JSON 後按 R（Hot Restart）無效。請完全停止 flutter run，然後用「Run and Debug」"
                          "選 fishing_map (Chrome + dart_defines.json) 重新 F5，或在終端執行："
                          "flutter run -d chrome --dart-define-from-file=dart_defines.json 。"
                          "並確認 JSON 頂層鍵名為 CWA_AUTHORIZATION（拼字須一致）。",
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: ok
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onErrorContainer,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(ThemeData theme, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(k, style: theme.textTheme.labelMedium),
          ),
          Expanded(child: Text(v, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  static String _formatWindBlock(SpotEnvironmentSnapshot e) {
    final parts = <String>[];
    if (e.windScaleZh != null && e.windScaleZh!.isNotEmpty) {
      parts.add("風級 ${e.windScaleZh}");
    }
    if (e.windKmh != null) {
      parts.add("${e.windKmh!.toStringAsFixed(0)} km/h");
    }
    if (e.windDirZh != null && e.windDirZh!.isNotEmpty) {
      parts.add(e.windDirZh!);
    }
    if (e.gustKmh != null) {
      parts.add("極風 ${e.gustKmh!.toStringAsFixed(0)} km/h");
    }
    if (e.maxWindScaleZh != null && e.maxWindScaleZh!.isNotEmpty) {
      parts.add("極風風級 ${e.maxWindScaleZh}");
    }
    if (parts.isEmpty) return "—";
    return parts.join(" · ");
  }

  static String _formatWaveHeightLine(SpotEnvironmentSnapshot e) {
    if (e.waveHeightM == null) {
      return "暫無浪高資料";
    }
    final h = "${e.waveHeightM!.toStringAsFixed(2)} m";
    final dir = e.waveDirZh;
    if (dir != null && dir.isNotEmpty) return "$h · $dir";
    return h;
  }

  static String _formatCurrentBlock(SpotEnvironmentSnapshot e) {
    final parts = <String>[];
    if (e.currentDirectionDescriptionZh != null &&
        e.currentDirectionDescriptionZh!.isNotEmpty) {
      parts.add(e.currentDirectionDescriptionZh!);
    } else if (e.currentDirectionZh != null &&
        e.currentDirectionZh!.isNotEmpty) {
      parts.add(e.currentDirectionZh!);
    }
    if (e.currentSpeedLabel != null && e.currentSpeedLabel!.isNotEmpty) {
      parts.add(e.currentSpeedLabel!);
    }
    if (e.currentSpeedKnotsLabel != null &&
        e.currentSpeedKnotsLabel!.isNotEmpty) {
      parts.add("${e.currentSpeedKnotsLabel!} 節");
    }
    return parts.isEmpty ? "—" : parts.join(" · ");
  }
}

