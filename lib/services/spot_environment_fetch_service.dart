import "dart:convert";

import "package:fishing_map/config/map_tokens.dart";
import "package:fishing_map/models/spot_environment_snapshot.dart";
import "package:fishing_map/utils/compass_zh.dart";
import "package:fishing_map/utils/moon_phase_zh.dart";
import "package:http/http.dart" as http;

const String _cwaSeaSurfacePreferred = "O-B0075-002";
const String _cwaSeaSurfaceFallback = "O-B0075-001";

/// 所選觀測時刻與 [when]（出釣／回溯時間）相差不超過此值，才接受 **002**；否則改試 **001**。
/// 使用 24 小時（非 48 小時），否則像「前天 23:00」對「明天凌晨 01:00」仍會被判在 48h 內而不會改用 001。
const Duration _kMaxObsAgeFromTarget = Duration(hours: 24);

/// 測站尚未更新時，API 可能回傳與目標時刻最接近的一筆但欄位多為 `None`／`-`；
/// 此時以 **1 小時**為步長往前（同測站、同回傳之時次清單）尋找仍有數值之觀測，最多回溯此小時數。
const int _kMaxObsHourlyBackfillHours = 48;

/// 釣點海象擷取：優先 [**O-B0075-002**]，若無「24 小時內」可對應觀測則改用 [O-B0075-001]（同 `SeaSurfaceObs` 結構）。
/// 須設定 [cwaAuthorization] 且座標在臺澎金馬粗略範圍內。
class SpotEnvironmentFetchService {
  SpotEnvironmentFetchService();

  Future<SpotEnvironmentSnapshot> fetchForInstant({
    required double lat,
    required double lng,
    required DateTime when,
    /// 與 `StationID.json` 綁定之最近測站代號；若 API 清單中有該站則優先擷取其潮水／海面觀測。
    String? linkedCwaStationId,
  }) async {
    final moon = moonPhaseLabelZh(when);
    final tideNote = SpotEnvironmentSnapshot.tideHintZh;
    final represents = when.toUtc().toIso8601String();

    if (cwaAuthorization.isEmpty || !_roughlyInTaiwan(lat, lng)) {
      return SpotEnvironmentSnapshot(
        moonPhaseZh: moon,
        tideNoteZh: tideNote,
        marineAvailable: false,
        representsInstantIso: represents,
        dataSourceNoteZh: cwaAuthorization.isEmpty
            ? "【中央氣象署】未帶入 CWA_AUTHORIZATION，無法擷取 $_cwaSeaSurfacePreferred／$_cwaSeaSurfaceFallback。"
            : "【中央氣象署】釣點座標不在臺澎金馬粗略範圍內，未呼叫海面觀測 API。",
        errorMessage: cwaAuthorization.isEmpty
            ? "請於編譯時帶入 CWA_AUTHORIZATION。"
            : "僅臺澎金馬範圍內可使用 O-B0075 系列資料集。",
      );
    }

    final obs002 = await _CwaOpenData.fetchSeaSurfaceObs(
      datasetId: _cwaSeaSurfacePreferred,
      auth: cwaAuthorization,
      targetLat: lat,
      targetLng: lng,
      when: when,
      preferStationId: linkedCwaStationId,
    );

    final fresh002 = obs002 != null &&
        _obsTimeWithin(
          of: obs002,
          reference: when,
          maxDelta: _kMaxObsAgeFromTarget,
        );

    _Ob0075Obs? obs;
    var datasetId = _cwaSeaSurfacePreferred;
    var usedFallback = false;
    var stale002Only = false;

    if (fresh002) {
      obs = obs002;
    } else {
      final obs001 = await _CwaOpenData.fetchSeaSurfaceObs(
        datasetId: _cwaSeaSurfaceFallback,
        auth: cwaAuthorization,
        targetLat: lat,
        targetLng: lng,
        when: when,
        preferStationId: linkedCwaStationId,
      );
      if (obs001 != null) {
        obs = obs001;
        datasetId = _cwaSeaSurfaceFallback;
        usedFallback = true;
      } else if (obs002 != null) {
        obs = obs002;
        datasetId = _cwaSeaSurfacePreferred;
        stale002Only = true;
      }
    }

    if (obs == null) {
      return SpotEnvironmentSnapshot(
        moonPhaseZh: moon,
        tideNoteZh: tideNote,
        marineAvailable: false,
        representsInstantIso: represents,
        dataSourceNoteZh:
            "【中央氣象署】$_cwaSeaSurfacePreferred 與 $_cwaSeaSurfaceFallback 皆無法取得可用 SeaSurfaceObs"
            "（002 可能無 ${_kMaxObsAgeFromTarget.inHours} 小時內可對應觀測或解析失敗；001 亦失敗）。"
            "請確認 JSON 結構、網路／逾時，且 opendata 已授權兩筆資料集。",
        errorMessage: "氣象署資料未取得",
      );
    }

    final srcNote = _buildSourceNote(
      obs,
      datasetId,
      usedFallback: usedFallback,
      stale002Only: stale002Only,
    );

    return SpotEnvironmentSnapshot(
      moonPhaseZh: moon,
      tideNoteZh: tideNote,
      tempC: obs.airTempC,
      humidityPct: null,
      windKmh: obs.windKmh,
      windDirZh: _windDirDisplay(obs),
      gustKmh: obs.maxWindKmh,
      precipitationMm: null,
      rainMm: null,
      weatherLabelZh: null,
      waveHeightM: obs.waveHeightM,
      waveDirZh: obs.waveDirZh,
      wavePeriodS: obs.wavePeriodS,
      seaSurfaceTempC: obs.seaTempC,
      marineAvailable: true,
      errorMessage: null,
      representsInstantIso: represents,
      dataSourceNoteZh: srcNote,
      cwaStationId: obs.stationId,
      cwaStationNameZh: obs.stationName,
      obsDataTimeIso: obs.obsDateTimeIso,
      tideHeightM: obs.tideHeightM,
      tideLevelZh: obs.tideLevelZh,
      stationPressureHpa: obs.stationPressureHpa,
      windScaleZh: obs.windScaleZh,
      maxWindScaleZh: obs.maxWindScaleZh,
      waveDirectionDescriptionZh: obs.waveDirectionDescriptionZh,
      currentDirectionZh: obs.currentDirectionZh,
      currentDirectionDescriptionZh: obs.currentDirectionDescriptionZh,
      currentSpeedLabel: obs.currentSpeedLabel,
      currentSpeedKnotsLabel: obs.currentSpeedKnotsLabel,
      layerNumber: obs.layerNumber,
      cardTideBuoySplit: false,
    );
  }

  /// 分別自最近潮位站、最近浮標擷取 O-B0075，合併為僅含：氣溫／潮位／潮汐／風級（潮位站）與浪高／海溫（浮標）。
  /// 快照設 [SpotEnvironmentSnapshot.cardTideBuoySplit] 為 true，供釣況卡精簡顯示。
  Future<SpotEnvironmentSnapshot> fetchMergedTideBuoyForInstant({
    required double lat,
    required double lng,
    required DateTime when,
    String? tideStationId,
    String? buoyStationId,
  }) async {
    final moon = moonPhaseLabelZh(when);
    final represents = when.toUtc().toIso8601String();

    if (cwaAuthorization.isEmpty || !_roughlyInTaiwan(lat, lng)) {
      return SpotEnvironmentSnapshot(
        moonPhaseZh: moon,
        tideNoteZh: null,
        marineAvailable: false,
        representsInstantIso: represents,
        dataSourceNoteZh: null,
        errorMessage: cwaAuthorization.isEmpty
            ? "請於編譯時帶入 CWA_AUTHORIZATION。"
            : "僅臺澎金馬範圍內可使用氣象與海象功能。",
        cardTideBuoySplit: true,
      );
    }

    final tid = tideStationId?.trim();
    final bid = buoyStationId?.trim();
    final tideObs = (tid != null && tid.isNotEmpty)
        ? await _fetchPreferredOb0075(
            lat: lat,
            lng: lng,
            when: when,
            preferStationId: tid,
          )
        : null;
    final buoyObs = (bid != null && bid.isNotEmpty)
        ? await _fetchPreferredOb0075(
            lat: lat,
            lng: lng,
            when: when,
            preferStationId: bid,
          )
        : null;

    if (tideObs == null && buoyObs == null) {
      return SpotEnvironmentSnapshot(
        moonPhaseZh: moon,
        tideNoteZh: null,
        marineAvailable: false,
        representsInstantIso: represents,
        dataSourceNoteZh: "【中央氣象署】潮位站／浮標站皆無法取得 O-B0075 觀測。",
        errorMessage: "氣象署資料未取得",
        cardTideBuoySplit: true,
      );
    }

    final lines = <String>[];
    if (tideObs != null) {
      final n = tideObs.stationName;
      lines.add(
        "潮位站 ${tideObs.stationId ?? ""}${n != null && n.isNotEmpty ? "（$n）" : ""}："
        "氣溫、潮位、潮汐、風級。",
      );
    }
    if (buoyObs != null) {
      final n = buoyObs.stationName;
      lines.add(
        "浮標站 ${buoyObs.stationId ?? ""}${n != null && n.isNotEmpty ? "（$n）" : ""}：浪高、海溫。",
      );
    }

    final hasAny = tideObs != null || buoyObs != null;

    return SpotEnvironmentSnapshot(
      moonPhaseZh: moon,
      tideNoteZh: null,
      tempC: tideObs?.airTempC,
      humidityPct: null,
      windKmh: null,
      windDirZh: null,
      gustKmh: null,
      precipitationMm: null,
      rainMm: null,
      weatherLabelZh: null,
      waveHeightM: buoyObs?.waveHeightM,
      waveDirZh: null,
      wavePeriodS: null,
      seaSurfaceTempC: buoyObs?.seaTempC,
      marineAvailable: hasAny,
      errorMessage: null,
      representsInstantIso: represents,
      dataSourceNoteZh: lines.join("\n"),
      cwaStationId: null,
      cwaStationNameZh: null,
      obsDataTimeIso: tideObs?.obsDateTimeIso ?? buoyObs?.obsDateTimeIso,
      tideHeightM: tideObs?.tideHeightM,
      tideLevelZh: tideObs?.tideLevelZh,
      stationPressureHpa: null,
      windScaleZh: tideObs?.windScaleZh,
      maxWindScaleZh: null,
      waveDirectionDescriptionZh: null,
      currentDirectionZh: null,
      currentDirectionDescriptionZh: null,
      currentSpeedLabel: null,
      currentSpeedKnotsLabel: null,
      layerNumber: null,
      cardTideBuoySplit: true,
    );
  }

  /// 與 [fetchForInstant] 相同之 002／001 選站邏輯，回傳單一 [_Ob0075Obs]。
  Future<_Ob0075Obs?> _fetchPreferredOb0075({
    required double lat,
    required double lng,
    required DateTime when,
    String? preferStationId,
  }) async {
    final obs002 = await _CwaOpenData.fetchSeaSurfaceObs(
      datasetId: _cwaSeaSurfacePreferred,
      auth: cwaAuthorization,
      targetLat: lat,
      targetLng: lng,
      when: when,
      preferStationId: preferStationId,
    );

    final fresh002 = obs002 != null &&
        _obsTimeWithin(
          of: obs002,
          reference: when,
          maxDelta: _kMaxObsAgeFromTarget,
        );

    _Ob0075Obs? obs;
    if (fresh002) {
      obs = obs002;
    } else {
      final obs001 = await _CwaOpenData.fetchSeaSurfaceObs(
        datasetId: _cwaSeaSurfaceFallback,
        auth: cwaAuthorization,
        targetLat: lat,
        targetLng: lng,
        when: when,
        preferStationId: preferStationId,
      );
      if (obs001 != null) {
        obs = obs001;
      } else {
        obs = obs002;
      }
    }
    return obs;
  }

  /// 所選觀測之 [obsDateTimeIso] 與 [reference] 相差不超過 [maxDelta]。
  static bool _obsTimeWithin({
    required _Ob0075Obs of,
    required DateTime reference,
    required Duration maxDelta,
  }) {
    final raw = of.obsDateTimeIso;
    if (raw == null || raw.isEmpty) return false;
    final t = DateTime.tryParse(raw);
    if (t == null) return false;
    return t.difference(reference).abs() <= maxDelta;
  }

  /// 風向：優先文字描述，否則度數轉十六方位。
  static String? _windDirDisplay(_Ob0075Obs o) {
    final d = o.windDirectionDescriptionZh;
    if (d != null && d.isNotEmpty) return d;
    return o.windDirZh;
  }

  String _buildSourceNote(
    _Ob0075Obs o,
    String datasetId, {
    required bool usedFallback,
    required bool stale002Only,
  }) {
    final sid = o.stationId ?? "?";
    final name = o.stationName;
    final head = name != null && name.isNotEmpty
        ? "【$datasetId】測站 $sid（$name）海面觀測。"
        : "【$datasetId】測站 $sid 海面觀測。";
    final why = usedFallback
        ? "因 $_cwaSeaSurfacePreferred 無與出釣時間相差 ${_kMaxObsAgeFromTarget.inHours} 小時內之可用觀測時次（或無法解析），改採 $_cwaSeaSurfaceFallback。"
        : stale002Only
            ? "$_cwaSeaSurfacePreferred 所回觀測時次已超過 ${_kMaxObsAgeFromTarget.inHours} 小時，"
                "且 $_cwaSeaSurfaceFallback 無法取得資料；以下仍顯示 $_cwaSeaSurfacePreferred 最接近時次。"
            : "";
    final sel = o.stationSelectionNote;
    final tail =
        "理想情況為依各測站 WGS84 座標選與釣點最近者；潮位隨地理位置不同，不應完全相同。";
    return [
      if (why.isNotEmpty) why,
      if (sel != null && sel.isNotEmpty) sel,
      head,
      tail,
    ].join("\n");
  }

  static bool _roughlyInTaiwan(double lat, double lng) {
    if (lat < 21.5 || lat > 26.5) return false;
    if (lng < 117.8 || lng > 123.8) return false;
    return true;
  }
}

// --- O-B0075 SeaSurfaceObs 解析（002／001 同構）---

class _Ob0075Obs {
  _Ob0075Obs({
    this.stationId,
    this.stationName,
    this.stationSelectionNote,
    this.obsDateTimeIso,
    this.tideHeightM,
    this.tideLevelZh,
    this.waveHeightM,
    this.waveDirZh,
    this.waveDirectionDescriptionZh,
    this.wavePeriodS,
    this.seaTempC,
    this.airTempC,
    this.stationPressureHpa,
    this.windKmh,
    this.windScaleZh,
    this.windDirZh,
    this.windDirectionDescriptionZh,
    this.maxWindKmh,
    this.maxWindScaleZh,
    this.currentDirectionZh,
    this.currentDirectionDescriptionZh,
    this.currentSpeedLabel,
    this.currentSpeedKnotsLabel,
    this.layerNumber,
  });

  final String? stationId;
  final String? stationName;

  /// 測站為經緯度選取、名稱粗配或列表第一筆之說明（供寫入資料來源）。
  final String? stationSelectionNote;
  final String? obsDateTimeIso;
  final double? tideHeightM;
  final String? tideLevelZh;
  final double? waveHeightM;
  final String? waveDirZh;
  final String? waveDirectionDescriptionZh;
  final double? wavePeriodS;
  final double? seaTempC;
  final double? airTempC;
  final double? stationPressureHpa;
  final double? windKmh;
  final String? windScaleZh;
  final String? windDirZh;
  final String? windDirectionDescriptionZh;
  final double? maxWindKmh;
  final String? maxWindScaleZh;
  final String? currentDirectionZh;
  final String? currentDirectionDescriptionZh;
  final String? currentSpeedLabel;
  final String? currentSpeedKnotsLabel;
  final int? layerNumber;
}

class _CwaOpenData {
  static Uri _datastoreUri(String id, String auth) {
    return Uri.https(
      "opendata.cwa.gov.tw",
      "/api/v1/rest/datastore/$id",
      {"Authorization": auth},
    );
  }

  static Future<Map<String, dynamic>?> _getJson(
    Uri uri, {
    Duration timeout = const Duration(seconds: 50),
  }) async {
    try {
      final res = await http.get(uri).timeout(timeout);
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  static dynamic _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k)) return m[k];
    }
    return null;
  }

  static Map<String, dynamic>? _asStrKeyMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) {
      return Map<String, dynamic>.from(
        v.map((k, val) => MapEntry("$k", val)),
      );
    }
    return null;
  }

  static bool _cwaReportSuccess(Map<String, dynamic> root) {
    final s = _pick(root, ["success", "Success"]);
    if (s == null) return true;
    if (s == true) return true;
    final t = s.toString().toLowerCase().trim();
    if (t == "true" || t == "1") return true;
    return false;
  }

  static String? _cleanStr(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final low = s.toLowerCase();
    if (low == "none" || low == "null" || s == "無" || s == "-") return null;
    return s;
  }

  static double? _parseDoubleObs(dynamic v) {
    if (v is num) return v.toDouble();
    final s = _cleanStr(v);
    if (s == null) return null;
    return double.tryParse(s);
  }

  static int? _parseIntObs(dynamic v) {
    final s = _cleanStr(v);
    if (s == null) return null;
    return int.tryParse(s);
  }

  /// 測站風速多為 m/s，與鄉鎮預報近似閾值換算 km/h。
  static double? _windMsMaybeToKmh(double? ms) {
    if (ms == null) return null;
    if (ms.abs() > 80) return ms;
    return ms * 3.6;
  }

  static double? _stationLat(Map<String, dynamic> st) {
    return _parseDoubleObs(
      _pick(st, [
        "StationLatitude",
        "stationLatitude",
        "Latitude",
        "latitude",
        "lat",
        "Lat",
      ]),
    );
  }

  static double? _stationLng(Map<String, dynamic> st) {
    return _parseDoubleObs(
      _pick(st, [
        "StationLongitude",
        "stationLongitude",
        "Longitude",
        "longitude",
        "lon",
        "Lon",
        "Lng",
      ]),
    );
  }

  /// 自 [Station] 擷取 WGS84（含 GeoInfo／Coordinates 等巢狀）。
  static (double?, double?) _coordsFromStation(Map<String, dynamic> st) {
    var la = _stationLat(st);
    var lo = _stationLng(st);
    if (la != null && lo != null) return (la, lo);

    final geo = _asStrKeyMap(
      _pick(st, ["GeoInfo", "geoInfo", "Geometry", "geometry", "GIS"]),
    );
    if (geo != null) {
      final coord = _asStrKeyMap(
        _pick(geo, [
          "Coordinates",
          "coordinates",
          "Coordinate",
          "coordinate",
        ]),
      );
      if (coord != null) {
        la = _parseDoubleObs(
          _pick(coord, [
            "StationLatitude",
            "stationLatitude",
            "Latitude",
            "latitude",
            "Lat",
          ]),
        );
        lo = _parseDoubleObs(
          _pick(coord, [
            "StationLongitude",
            "stationLongitude",
            "Longitude",
            "longitude",
            "Lon",
            "Lng",
          ]),
        );
        if (la != null && lo != null) return (la, lo);
      }
      la = _stationLat(geo);
      lo = _stationLng(geo);
      if (la != null && lo != null) return (la, lo);
    }

    for (final v in st.values) {
      if (v is Map) {
        final m = _asStrKeyMap(v);
        if (m == null) continue;
        la = _stationLat(m);
        lo = _stationLng(m);
        if (la != null && lo != null) return (la, lo);
      }
    }
    return (null, null);
  }

  /// [Location] 測站或本層之經緯度。
  static (double?, double?) _coordsFromLocation(Map<String, dynamic> loc) {
    final st = _asStrKeyMap(_pick(loc, ["Station", "station"]));
    if (st != null) {
      final p = _coordsFromStation(st);
      if (p.$1 != null && p.$2 != null) return p;
    }
    return (_stationLat(loc), _stationLng(loc));
  }

  /// 與釣點最近之參考點（基隆、花蓮、蘇澳）用於名稱加權。
  static const double _refKeelLat = 25.13;
  static const double _refKeelLng = 121.74;
  static const double _refHualLat = 23.98;
  static const double _refHualLng = 121.60;
  static const double _refSuaoLat = 24.596;
  static const double _refSuaoLng = 121.852;

  static const List<String> _northCoastNameHints = [
    "基隆",
    "萬里",
    "金山",
    "石門",
    "富貴角",
    "三貂",
    "鼻頭",
    "龍洞",
    "萊萊",
    "彭佳嶼",
    "北海岸",
  ];

  static const List<String> _eastCoastNameHints = [
    "花蓮",
    "和平",
    "鹽寮",
    "石梯",
    "豐濱",
    "磯崎",
    "立霧",
  ];

  static const List<String> _northEastNameHints = [
    "蘇澳",
    "宜蘭",
    "頭城",
    "龜山",
    "礁溪",
  ];

  /// API 未附經緯度時，依釣點與測站名稱粗配（北海岸 vs 東海岸 keyword）。
  static Map<String, dynamic>? _pickLocationByStationNameHeuristic(
    List<Map<String, dynamic>> locs,
    double targetLat,
    double targetLng,
  ) {
    if (locs.isEmpty) return null;
    final dKeel =
        _dist2(targetLat, targetLng, _refKeelLat, _refKeelLng);
    final dHual =
        _dist2(targetLat, targetLng, _refHualLat, _refHualLng);
    final dSu = _dist2(targetLat, targetLng, _refSuaoLat, _refSuaoLng);
    var m = dKeel;
    if (dHual < m) m = dHual;
    if (dSu < m) m = dSu;
    final preferNorth = m == dKeel;
    final preferEast = m == dHual;
    final preferNe = m == dSu;

    Map<String, dynamic>? best;
    var bestScore = -1;
    for (final loc in locs) {
      if (_obsTimeSlots(loc).isEmpty) continue;
      final st = _asStrKeyMap(_pick(loc, ["Station", "station"]));
      final name =
          _cleanStr(_pick(st ?? {}, ["StationName", "stationName"])) ?? "";
      var score = 0;
      if (preferNorth) {
        for (final k in _northCoastNameHints) {
          if (name.contains(k)) score += 15;
        }
      } else if (preferEast) {
        for (final k in _eastCoastNameHints) {
          if (name.contains(k)) score += 15;
        }
      } else if (preferNe) {
        for (final k in _northEastNameHints) {
          if (name.contains(k)) score += 12;
        }
      }
      if (score == 0) {
        for (final k in _northCoastNameHints) {
          if (name.contains(k)) score += 5;
        }
        for (final k in _eastCoastNameHints) {
          if (name.contains(k)) score += 5;
        }
        for (final k in _northEastNameHints) {
          if (name.contains(k)) score += 5;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        best = loc;
      }
    }
    return bestScore > 0 ? best : null;
  }

  static double _dist2(double a1, double o1, double a2, double o2) {
    final da = a1 - a2;
    final doy = o1 - o2;
    return da * da + doy * doy;
  }

  static List<Map<String, dynamic>> _locationList(Map<String, dynamic> root) {
    final rec = _asStrKeyMap(_pick(root, ["records", "Records"]));
    if (rec == null) return [];
    final sso = _asStrKeyMap(
      _pick(rec, ["SeaSurfaceObs", "seaSurfaceObs"]),
    );
    if (sso == null) return [];
    final loc = _pick(sso, ["Location", "location"]);
    if (loc is! List) return [];
    return loc.map(_asStrKeyMap).whereType<Map<String, dynamic>>().toList();
  }

  static List<Map<String, dynamic>> _obsTimeSlots(Map<String, dynamic> loc) {
    final times = _asStrKeyMap(
      _pick(loc, ["StationObsTimes", "stationObsTimes"]),
    );
    if (times == null) return [];
    final raw = _pick(times, ["StationObsTime", "stationObsTime"]);
    if (raw is List) {
      return raw.map(_asStrKeyMap).whereType<Map<String, dynamic>>().toList();
    }
    if (raw is Map<String, dynamic>) return [raw];
    return [];
  }

  static DateTime? _slotTime(Map<String, dynamic> slot) {
    final raw = _pick(slot, ["DateTime", "dateTime", "DataTime", "dataTime"]);
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  static Map<String, dynamic> _flattenWeatherElements(Map<String, dynamic> we) {
    final out = Map<String, dynamic>.from(we);
    final pa = _asStrKeyMap(
      out.remove("PrimaryAnemometer") ??
          out.remove("primaryAnemometer"),
    );
    if (pa != null) {
      for (final e in pa.entries) {
        if (!out.containsKey(e.key)) out[e.key] = e.value;
      }
    }
    return out;
  }

  /// 清單中比對 [StationID]（忽略大小寫）；僅採有至少一筆觀測時次之測站。
  static Map<String, dynamic>? _locationMatchingStationId(
    List<Map<String, dynamic>> locs,
    String wantId,
  ) {
    final a = wantId.trim();
    if (a.isEmpty) return null;
    final low = a.toLowerCase();
    for (final loc in locs) {
      if (_obsTimeSlots(loc).isEmpty) continue;
      final st = _asStrKeyMap(_pick(loc, ["Station", "station"]));
      final sid = _cleanStr(
        _pick(st ?? {}, [
          "StationID",
          "stationID",
          "StationId",
          "stationId",
        ]),
      );
      if (sid == null) continue;
      if (sid == a || sid.toLowerCase() == low) return loc;
    }
    return null;
  }

  static Map<String, dynamic>? _pickNearestObs(
    List<Map<String, dynamic>> slots,
    DateTime when,
  ) {
    if (slots.isEmpty) return null;
    Map<String, dynamic>? best;
    var bestAbs = double.infinity;
    for (final s in slots) {
      final dt = _slotTime(s);
      if (dt == null) continue;
      final abs = dt.difference(when).inMinutes.abs().toDouble();
      if (abs < bestAbs) {
        bestAbs = abs;
        best = s;
      }
    }
    return best ?? slots.first;
  }

  /// 與 [anchor] 落在同一 **UTC 日曆小時**（整點對齊）之觀測時次，供「以小時為單位」回溯。
  static bool _sameUtcHour(DateTime a, DateTime b) {
    final au = a.toUtc();
    final bu = b.toUtc();
    return au.year == bu.year &&
        au.month == bu.month &&
        au.day == bu.day &&
        au.hour == bu.hour;
  }

  /// 氣象署尚未寫入數值時常見 `None`、`-` 等；[_cleanStr]／[_parseDoubleObs] 已濾除，此處彙整是否仍全無可用欄位。
  static bool _ob0075SlotLooksMostlyEmpty(Map<String, dynamic> slot) {
    final weRaw = _asStrKeyMap(
      _pick(slot, ["WeatherElements", "weatherElements"]),
    );
    if (weRaw == null) return true;
    final f = _flattenWeatherElements(weRaw);
    final tideH = _parseDoubleObs(_pick(f, ["TideHeight", "tideHeight"]));
    final tideLv = _cleanStr(_pick(f, ["TideLevel", "tideLevel"]));
    final waveH = _parseDoubleObs(_pick(f, ["WaveHeight", "waveHeight"]));
    final wavePer = _parseDoubleObs(_pick(f, ["WavePeriod", "wavePeriod"]));
    final waveDirDesc = _cleanStr(
      _pick(f, ["WaveDirectionDescription", "waveDirectionDescription"]),
    );
    final seaT = _parseDoubleObs(_pick(f, ["SeaTemperature", "seaTemperature"]));
    final airT = _parseDoubleObs(_pick(f, ["Temperature", "temperature"]));
    final press = _parseDoubleObs(
      _pick(f, ["StationPressure", "stationPressure"]),
    );
    final wMs = _parseDoubleObs(_pick(f, ["WindSpeed", "windSpeed"]));
    final wScale = _cleanStr(_pick(f, ["WindScale", "windScale"]));
    final wDirZh = _windDirZhFromFlat(f);
    final wDirD = _cleanStr(
      _pick(f, [
        "WindDirectionDescription",
        "windDirectionDescription",
      ]),
    );
    final maxW = _parseDoubleObs(
      _pick(f, ["MaximumWindSpeed", "maximumWindSpeed"]),
    );
    final maxScale = _cleanStr(
      _pick(f, ["MaximumWindScale", "maximumWindScale"]),
    );
    final cDir = _cleanStr(_pick(f, ["CurrentDirection", "currentDirection"]));
    final cDirD = _cleanStr(
      _pick(f, [
        "CurrentDirectionDescription",
        "currentDirectionDescription",
      ]),
    );
    final cSp = _cleanStr(_pick(f, ["CurrentSpeed", "currentSpeed"]));
    final cKn = _cleanStr(
      _pick(f, ["CurrentSpeedInKnots", "currentSpeedInKnots"]),
    );
    final layer = _parseIntObs(_pick(f, ["LayerNumber", "layerNumber"]));
    final hasAny = tideH != null ||
        tideLv != null ||
        waveH != null ||
        wavePer != null ||
        waveDirDesc != null ||
        seaT != null ||
        airT != null ||
        press != null ||
        wMs != null ||
        wScale != null ||
        wDirZh != null ||
        wDirD != null ||
        maxW != null ||
        maxScale != null ||
        cDir != null ||
        cDirD != null ||
        cSp != null ||
        cKn != null ||
        layer != null;
    return !hasAny;
  }

  /// 先以 [when]、[when-1h]… 之 **UTC 小時**為錨，在**不晚於 [when]** 的時次中找同錨點小時內最接近錨點且非空之觀測；否則改採不晚於 [when] 之最新一筆非空；再否則維持最近時次。
  static Map<String, dynamic>? _pickSlotWithHourlyBackfill(
    List<Map<String, dynamic>> slots,
    DateTime when,
  ) {
    if (slots.isEmpty) return null;
    for (var h = 0; h <= _kMaxObsHourlyBackfillHours; h++) {
      final anchor = when.subtract(Duration(hours: h));
      Map<String, dynamic>? best;
      var bestDist = double.infinity;
      for (final s in slots) {
        final dt = _slotTime(s);
        if (dt == null || dt.isAfter(when)) continue;
        if (!_sameUtcHour(dt, anchor)) continue;
        if (_ob0075SlotLooksMostlyEmpty(s)) continue;
        final d = dt.difference(anchor).inMinutes.abs().toDouble();
        if (d < bestDist) {
          bestDist = d;
          best = s;
        }
      }
      if (best != null) return best;
    }
    final dated = <({DateTime t, Map<String, dynamic> s})>[];
    for (final s in slots) {
      final dt = _slotTime(s);
      if (dt == null || dt.isAfter(when)) continue;
      dated.add((t: dt, s: s));
    }
    dated.sort((a, b) => b.t.compareTo(a.t));
    for (final row in dated) {
      if (!_ob0075SlotLooksMostlyEmpty(row.s)) return row.s;
    }
    return _pickNearestObs(slots, when);
  }

  static String? _waveDirZhFromFlat(Map<String, dynamic> f) {
    final desc = _cleanStr(
      _pick(f, [
        "WaveDirectionDescription",
        "waveDirectionDescription",
      ]),
    );
    if (desc != null) return desc;
    final raw = _cleanStr(
      _pick(f, ["WaveDirection", "waveDirection"]),
    );
    if (raw == null) return null;
    final deg = double.tryParse(raw);
    if (deg != null) return direction16Zh(deg);
    if (RegExp(r"[北南東西]").hasMatch(raw)) return raw;
    return raw;
  }

  static String? _windDirZhFromFlat(Map<String, dynamic> f) {
    final desc = _cleanStr(
      _pick(f, [
        "WindDirectionDescription",
        "windDirectionDescription",
      ]),
    );
    if (desc != null) return desc;
    final raw = _cleanStr(
      _pick(f, ["WindDirection", "windDirection"]),
    );
    if (raw == null) return null;
    final deg = double.tryParse(raw);
    if (deg != null) return direction16Zh(deg);
    return raw;
  }

  static Future<_Ob0075Obs?> fetchSeaSurfaceObs({
    required String datasetId,
    required String auth,
    required double targetLat,
    required double targetLng,
    required DateTime when,
    String? preferStationId,
  }) async {
    if (auth.isEmpty) return null;
    final uri = _datastoreUri(datasetId, auth);
    final root = await _getJson(uri);
    if (root == null) return null;
    if (!_cwaReportSuccess(root)) return null;

    final locs = _locationList(root);
    if (locs.isEmpty) return null;

    String? want = _cleanStr(preferStationId);

    Map<String, dynamic>? byWantedId;
    String? selectionNotePre;
    if (want != null && want.isNotEmpty) {
      byWantedId = _locationMatchingStationId(locs, want);
      if (byWantedId != null) {
        selectionNotePre =
            "已依釣點綁定之觀測站代號「$want」（與 StationID.json 最近測站對應）擷取本資料集該測站觀測。";
      } else {
        selectionNotePre =
            "綁定之觀測站代號「$want」未見於本次 API 回傳清單，已改以座標／名稱規則重選測站。";
      }
    }

    Map<String, dynamic>? nearestCoordLoc;
    var bestD2 = double.infinity;
    for (final loc in locs) {
      final p = _coordsFromLocation(loc);
      final la = p.$1;
      final lo = p.$2;
      if (la == null || lo == null) continue;
      final d2 = _dist2(la, lo, targetLat, targetLng);
      if (d2 < bestD2) {
        bestD2 = d2;
        nearestCoordLoc = loc;
      }
    }

    final Map<String, dynamic> chosenLoc;
    final String? selectionNote;
    if (byWantedId != null) {
      chosenLoc = byWantedId;
      selectionNote = selectionNotePre;
    } else if (nearestCoordLoc != null) {
      chosenLoc = nearestCoordLoc;
      selectionNote = selectionNotePre;
    } else {
      final byName = _pickLocationByStationNameHeuristic(
        locs,
        targetLat,
        targetLng,
      );
      if (byName != null) {
        chosenLoc = byName;
        selectionNote = [
          if (selectionNotePre != null) selectionNotePre,
          "本資料集部分測站未附經緯度，已依釣點所在海岸區域與「測站名稱」粗配；"
              "北海岸／花蓮東岸等應會對應不同測站。若名稱不含地區關鍵字，仍可能重複。",
        ].join("\n");
      } else {
        chosenLoc = locs.firstWhere(
          (l) => _obsTimeSlots(l).isNotEmpty,
          orElse: () => locs.first,
        );
        selectionNote = [
          if (selectionNotePre != null) selectionNotePre,
          "無法比對測站座標或海岸關鍵字，已使用清單順序第一筆有觀測之測站；"
              "不同釣點可能顯示相同潮位，建議確認 API 是否提供測站座標。",
        ].where((s) => s.isNotEmpty).join("\n");
      }
    }

    final slots = _obsTimeSlots(chosenLoc);
    final slot = _pickSlotWithHourlyBackfill(slots, when);
    if (slot == null) return null;

    final st = _asStrKeyMap(_pick(chosenLoc, ["Station", "station"]));
    final weRaw = _asStrKeyMap(
      _pick(slot, ["WeatherElements", "weatherElements"]),
    );
    if (weRaw == null) return null;
    final f = _flattenWeatherElements(weRaw);

    final sid = _cleanStr(_pick(st ?? {}, ["StationID", "stationID", "StationId", "stationId"]));
    final sname = _cleanStr(_pick(st ?? {}, ["StationName", "stationName"]));
    final obsIso = _cleanStr(_pick(slot, ["DateTime", "dateTime"]));

    final tideH = _parseDoubleObs(_pick(f, ["TideHeight", "tideHeight"]));
    final tideLv = _cleanStr(_pick(f, ["TideLevel", "tideLevel"]));
    final waveH = _parseDoubleObs(_pick(f, ["WaveHeight", "waveHeight"]));
    final wavePer = _parseDoubleObs(_pick(f, ["WavePeriod", "wavePeriod"]));
    final waveDirDesc = _cleanStr(
      _pick(f, ["WaveDirectionDescription", "waveDirectionDescription"]),
    );
    final wDirZh = _waveDirZhFromFlat(f);

    final seaT = _parseDoubleObs(_pick(f, ["SeaTemperature", "seaTemperature"]));
    final airT = _parseDoubleObs(_pick(f, ["Temperature", "temperature"]));
    final press = _parseDoubleObs(
      _pick(f, ["StationPressure", "stationPressure"]),
    );

    final wMs = _parseDoubleObs(_pick(f, ["WindSpeed", "windSpeed"]));
    final wKmh = _windMsMaybeToKmh(wMs);
    final wScale = _cleanStr(_pick(f, ["WindScale", "windScale"]));
    final wDir = _windDirZhFromFlat(f);
    final wDirD = _cleanStr(
      _pick(f, [
        "WindDirectionDescription",
        "windDirectionDescription",
      ]),
    );
    final maxW = _parseDoubleObs(
      _pick(f, ["MaximumWindSpeed", "maximumWindSpeed"]),
    );
    final maxWKmh = _windMsMaybeToKmh(maxW);
    final maxScale = _cleanStr(
      _pick(f, ["MaximumWindScale", "maximumWindScale"]),
    );

    final cDir = _cleanStr(_pick(f, ["CurrentDirection", "currentDirection"]));
    final cDirD = _cleanStr(
      _pick(f, [
        "CurrentDirectionDescription",
        "currentDirectionDescription",
      ]),
    );
    final cSp = _cleanStr(_pick(f, ["CurrentSpeed", "currentSpeed"]));
    final cKn = _cleanStr(
      _pick(f, ["CurrentSpeedInKnots", "currentSpeedInKnots"]),
    );
    final layer = _parseIntObs(_pick(f, ["LayerNumber", "layerNumber"]));

    return _Ob0075Obs(
      stationId: sid,
      stationName: sname,
      stationSelectionNote: selectionNote,
      obsDateTimeIso: obsIso,
      tideHeightM: tideH,
      tideLevelZh: tideLv,
      waveHeightM: waveH,
      waveDirZh: wDirZh,
      waveDirectionDescriptionZh: waveDirDesc,
      wavePeriodS: wavePer,
      seaTempC: seaT,
      airTempC: airT,
      stationPressureHpa: press,
      windKmh: wKmh,
      windScaleZh: wScale,
      windDirZh: wDir,
      windDirectionDescriptionZh: wDirD,
      maxWindKmh: maxWKmh,
      maxWindScaleZh: maxScale,
      currentDirectionZh: cDir,
      currentDirectionDescriptionZh: cDirD,
      currentSpeedLabel: cSp,
      currentSpeedKnotsLabel: cKn,
      layerNumber: layer,
    );
  }
}
