/// 氣象／海象快照（可序列化到本機／Firestore）。O-B0075 海面測站觀測其餘欄位見下方專用屬性。
class SpotEnvironmentSnapshot {
  SpotEnvironmentSnapshot({
    required this.moonPhaseZh,
    this.tideNoteZh,
    this.tempC,
    this.humidityPct,
    this.windKmh,
    this.windDirZh,
    this.gustKmh,
    this.precipitationMm,
    this.rainMm,
    this.weatherLabelZh,
    this.waveHeightM,
    this.waveDirZh,
    this.wavePeriodS,
    this.seaSurfaceTempC,
    this.marineAvailable = true,
    this.errorMessage,
    this.representsInstantIso,
    this.dataSourceNoteZh,
    this.cwaStationId,
    this.cwaStationNameZh,
    this.obsDataTimeIso,
    this.tideHeightM,
    this.tideLevelZh,
    this.stationPressureHpa,
    this.windScaleZh,
    this.maxWindScaleZh,
    this.waveDirectionDescriptionZh,
    this.currentDirectionZh,
    this.currentDirectionDescriptionZh,
    this.currentSpeedLabel,
    this.currentSpeedKnotsLabel,
    this.layerNumber,
    this.cardTideBuoySplit = false,
  });

  final String moonPhaseZh;
  final String? tideNoteZh;

  final double? tempC;
  final double? humidityPct;
  final double? windKmh;
  final String? windDirZh;
  final double? gustKmh;
  final double? precipitationMm;
  final double? rainMm;
  final String? weatherLabelZh;
  final double? waveHeightM;
  final String? waveDirZh;
  final double? wavePeriodS;
  final double? seaSurfaceTempC;
  final bool marineAvailable;

  final String? errorMessage;

  final String? representsInstantIso;
  final String? dataSourceNoteZh;

  /// 海面測站代號（O-B0075 系列）。
  final String? cwaStationId;

  /// 測站名稱（若 API 提供）。
  final String? cwaStationNameZh;

  /// API 所選觀測時次（ISO 字串）。
  final String? obsDataTimeIso;

  /// 潮位（公尺）。
  final double? tideHeightM;

  /// 漲退潮描述（例：退潮）。
  final String? tideLevelZh;

  final double? stationPressureHpa;

  /// 蒲福風級等字串。
  final String? windScaleZh;

  /// 最大風蒲福風級。
  final String? maxWindScaleZh;

  /// 浪向文字描述。
  final String? waveDirectionDescriptionZh;

  /// 海流方向（度或代碼字串，依 API）。
  final String? currentDirectionZh;

  final String? currentDirectionDescriptionZh;

  /// 海流速度（原欄位字串，單位依 API）。
  final String? currentSpeedLabel;

  /// 海流速度（節，原欄位字串）。
  final String? currentSpeedKnotsLabel;

  final int? layerNumber;

  /// 為 true 時釣況卡僅顯示：潮位站之氣溫／潮位／潮汐／風級，與浮標之浪高／海溫（新增釣點合併擷取）。
  final bool cardTideBuoySplit;

  static const attribution =
      "釣況卡資料來自交通部中央氣象署開放資料（優先 O-B0075-002，必要時 O-B0075-001；海面測站／須授權），僅供參考。";

  static const tideHintZh =
      "縣市潮汐預報可至「交通部中央氣象署」開放資料平臺串接（如資料集 F-A0021），需申請 Authorization。";

  Map<String, dynamic> toJson() => {
        "moonPhaseZh": moonPhaseZh,
        if (tideNoteZh != null) "tideNoteZh": tideNoteZh,
        if (tempC != null) "tempC": tempC,
        if (humidityPct != null) "humidityPct": humidityPct,
        if (windKmh != null) "windKmh": windKmh,
        if (windDirZh != null) "windDirZh": windDirZh,
        if (gustKmh != null) "gustKmh": gustKmh,
        if (precipitationMm != null) "precipitationMm": precipitationMm,
        if (rainMm != null) "rainMm": rainMm,
        if (weatherLabelZh != null) "weatherLabelZh": weatherLabelZh,
        if (waveHeightM != null) "waveHeightM": waveHeightM,
        if (waveDirZh != null) "waveDirZh": waveDirZh,
        if (wavePeriodS != null) "wavePeriodS": wavePeriodS,
        if (seaSurfaceTempC != null) "seaSurfaceTempC": seaSurfaceTempC,
        "marineAvailable": marineAvailable,
        if (errorMessage != null) "errorMessage": errorMessage,
        if (representsInstantIso != null) "representsInstantIso": representsInstantIso,
        if (dataSourceNoteZh != null) "dataSourceNoteZh": dataSourceNoteZh,
        if (cwaStationId != null) "cwaStationId": cwaStationId,
        if (cwaStationNameZh != null) "cwaStationNameZh": cwaStationNameZh,
        if (obsDataTimeIso != null) "obsDataTimeIso": obsDataTimeIso,
        if (tideHeightM != null) "tideHeightM": tideHeightM,
        if (tideLevelZh != null) "tideLevelZh": tideLevelZh,
        if (stationPressureHpa != null) "stationPressureHpa": stationPressureHpa,
        if (windScaleZh != null) "windScaleZh": windScaleZh,
        if (maxWindScaleZh != null) "maxWindScaleZh": maxWindScaleZh,
        if (waveDirectionDescriptionZh != null)
          "waveDirectionDescriptionZh": waveDirectionDescriptionZh,
        if (currentDirectionZh != null) "currentDirectionZh": currentDirectionZh,
        if (currentDirectionDescriptionZh != null)
          "currentDirectionDescriptionZh": currentDirectionDescriptionZh,
        if (currentSpeedLabel != null) "currentSpeedLabel": currentSpeedLabel,
        if (currentSpeedKnotsLabel != null)
          "currentSpeedKnotsLabel": currentSpeedKnotsLabel,
        if (layerNumber != null) "layerNumber": layerNumber,
        "cardTideBuoySplit": cardTideBuoySplit,
      };

  SpotEnvironmentSnapshot prependSourceNote(String prefix) {
    final tail = dataSourceNoteZh;
    return SpotEnvironmentSnapshot(
      moonPhaseZh: moonPhaseZh,
      tideNoteZh: tideNoteZh,
      tempC: tempC,
      humidityPct: humidityPct,
      windKmh: windKmh,
      windDirZh: windDirZh,
      gustKmh: gustKmh,
      precipitationMm: precipitationMm,
      rainMm: rainMm,
      weatherLabelZh: weatherLabelZh,
      waveHeightM: waveHeightM,
      waveDirZh: waveDirZh,
      wavePeriodS: wavePeriodS,
      seaSurfaceTempC: seaSurfaceTempC,
      marineAvailable: marineAvailable,
      errorMessage: errorMessage,
      representsInstantIso: representsInstantIso,
      dataSourceNoteZh: tail == null || tail.isEmpty ? prefix : "$prefix\n$tail",
      cwaStationId: cwaStationId,
      cwaStationNameZh: cwaStationNameZh,
      obsDataTimeIso: obsDataTimeIso,
      tideHeightM: tideHeightM,
      tideLevelZh: tideLevelZh,
      stationPressureHpa: stationPressureHpa,
      windScaleZh: windScaleZh,
      maxWindScaleZh: maxWindScaleZh,
      waveDirectionDescriptionZh: waveDirectionDescriptionZh,
      currentDirectionZh: currentDirectionZh,
      currentDirectionDescriptionZh: currentDirectionDescriptionZh,
      currentSpeedLabel: currentSpeedLabel,
      currentSpeedKnotsLabel: currentSpeedKnotsLabel,
      layerNumber: layerNumber,
      cardTideBuoySplit: cardTideBuoySplit,
    );
  }

  static SpotEnvironmentSnapshot fromJson(Map<String, dynamic> m) {
    double? gv(String k) {
      final v = m[k];
      if (v is num) return v.toDouble();
      return null;
    }

    int? gInt(String k) {
      final v = m[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return null;
    }

    return SpotEnvironmentSnapshot(
      moonPhaseZh: m["moonPhaseZh"] as String? ?? "",
      tideNoteZh: m["tideNoteZh"] as String?,
      tempC: gv("tempC"),
      humidityPct: gv("humidityPct"),
      windKmh: gv("windKmh"),
      windDirZh: m["windDirZh"] as String?,
      gustKmh: gv("gustKmh"),
      precipitationMm: gv("precipitationMm"),
      rainMm: gv("rainMm"),
      weatherLabelZh: m["weatherLabelZh"] as String?,
      waveHeightM: gv("waveHeightM"),
      waveDirZh: m["waveDirZh"] as String?,
      wavePeriodS: gv("wavePeriodS"),
      seaSurfaceTempC: gv("seaSurfaceTempC"),
      marineAvailable: m["marineAvailable"] as bool? ?? true,
      errorMessage: m["errorMessage"] as String?,
      representsInstantIso: m["representsInstantIso"] as String?,
      dataSourceNoteZh: m["dataSourceNoteZh"] as String?,
      cwaStationId: m["cwaStationId"] as String?,
      cwaStationNameZh: m["cwaStationNameZh"] as String?,
      obsDataTimeIso: m["obsDataTimeIso"] as String?,
      tideHeightM: gv("tideHeightM"),
      tideLevelZh: m["tideLevelZh"] as String?,
      stationPressureHpa: gv("stationPressureHpa"),
      windScaleZh: m["windScaleZh"] as String?,
      maxWindScaleZh: m["maxWindScaleZh"] as String?,
      waveDirectionDescriptionZh: m["waveDirectionDescriptionZh"] as String?,
      currentDirectionZh: m["currentDirectionZh"] as String?,
      currentDirectionDescriptionZh: m["currentDirectionDescriptionZh"] as String?,
      currentSpeedLabel: m["currentSpeedLabel"] as String?,
      currentSpeedKnotsLabel: m["currentSpeedKnotsLabel"] as String?,
      layerNumber: gInt("layerNumber"),
      cardTideBuoySplit: m["cardTideBuoySplit"] as bool? ?? false,
    );
  }
}
