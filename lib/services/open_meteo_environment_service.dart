import "dart:convert";

import "package:fishing_map/models/spot_environment_snapshot.dart";
import "package:fishing_map/utils/compass_zh.dart";
import "package:fishing_map/utils/moon_phase_zh.dart";
import "package:http/http.dart" as http;

String _wmoWeatherZh(int code) {
  if (code == 0) return "晴朗";
  if (code >= 1 && code <= 3) return "多雲";
  if (code == 45 || code == 48) return "霧";
  if (code == 51 || code == 53 || code == 55) return "毛毛雨";
  if (code == 56 || code == 57) return "凍毛毛雨";
  if (code == 61 || code == 63 || code == 65) return "雨";
  if (code == 66 || code == 67) return "凍雨";
  if (code == 71 || code == 73 || code == 75) return "雪";
  if (code == 77) return "雪粒";
  if (code == 80 || code == 81 || code == 82) return "陣雨";
  if (code == 85 || code == 86) return "陣雪";
  if (code == 95) return "雷雨";
  if (code == 96 || code == 99) return "雷雨伴有冰雹";
  return "天氣代碼 $code";
}

String _ymd(DateTime d) =>
    "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

class OpenMeteoEnvironmentService {
  /// 目前時段（與舊版相容）。
  Future<SpotEnvironmentSnapshot> fetch({
    required double lat,
    required double lng,
    DateTime? refTime,
  }) async {
    final t = refTime ?? DateTime.now();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    return _fetchCurrent(
      lat: lat,
      lng: lng,
      moon: moonPhaseLabelZh(t),
      tideNote: SpotEnvironmentSnapshot.tideHintZh,
      representsInstantIso: nowIso,
      dataSourceNoteZh: "開啟畫面當下（即時）",
    );
  }

  /// 歷史／預報時段：以 [when] 在 Asia/Taipei 該日之 hourly 最接近一小時資料（含海況）。
  Future<SpotEnvironmentSnapshot> fetchForInstant({
    required double lat,
    required double lng,
    required DateTime when,
  }) async {
    final moon = moonPhaseLabelZh(when);
    const tideNote = SpotEnvironmentSnapshot.tideHintZh;
    final represents = when.toUtc().toIso8601String();

    final dayStart =
        DateTime(when.year, when.month, when.day); // 用本地日界切資料請求範圍
    final ymd = _ymd(dayStart);

    try {
      final wHourly = await _getJson(
        Uri.https("api.open-meteo.com", "/v1/forecast", {
          "latitude": "$lat",
          "longitude": "$lng",
          "hourly":
              "temperature_2m,relative_humidity_2m,weather_code,precipitation,rain,wind_speed_10m,wind_direction_10m,wind_gusts_10m",
          "timezone": "Asia/Taipei",
          "wind_speed_unit": "kmh",
          "start_date": ymd,
          "end_date": ymd,
        }),
      );

      SpotEnvironmentSnapshot? weatherSnap;
      if (wHourly != null) {
        final hw = wHourly["hourly"] as Map<String, dynamic>?;
        weatherSnap = _snapshotFromHourlyWeather(
          hw,
          when,
          moon,
          tideNote,
          represents,
          "指定時間（${when.year}/${when.month}/${when.day} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')} 附近）",
        );
      }

      final mHourly = await _getJson(
        Uri.https("marine-api.open-meteo.com", "/v1/marine", {
          "latitude": "$lat",
          "longitude": "$lng",
          "hourly": "wave_height,wave_direction,wave_period,sea_surface_temperature",
          "timezone": "Asia/Taipei",
          "start_date": ymd,
          "end_date": ymd,
        }),
      );

      double? wh;
      String? wdz;
      double? wp;
      double? sst;
      var marineOk = false;
      if (mHourly != null) {
        final mh = mHourly["hourly"] as Map<String, dynamic>?;
        final idx = _nearestHourlyIndex(mh?["time"], when);
        if (idx != null) {
          marineOk = true;
          wh = _hourlyDouble(mh, "wave_height", idx);
          final wd = _hourlyDouble(mh, "wave_direction", idx);
          wdz = direction16Zh(wd);
          wp = _hourlyDouble(mh, "wave_period", idx);
          sst = _hourlyDouble(mh, "sea_surface_temperature", idx);
        }
      }

      if (weatherSnap != null) {
        return SpotEnvironmentSnapshot(
          moonPhaseZh: weatherSnap.moonPhaseZh,
          tideNoteZh: weatherSnap.tideNoteZh,
          tempC: weatherSnap.tempC,
          humidityPct: weatherSnap.humidityPct,
          windKmh: weatherSnap.windKmh,
          windDirZh: weatherSnap.windDirZh,
          gustKmh: weatherSnap.gustKmh,
          precipitationMm: weatherSnap.precipitationMm,
          rainMm: weatherSnap.rainMm,
          weatherLabelZh: weatherSnap.weatherLabelZh,
          waveHeightM: wh,
          waveDirZh: wdz,
          wavePeriodS: wp,
          seaSurfaceTempC: sst,
          marineAvailable: marineOk,
          errorMessage: weatherSnap.errorMessage,
          representsInstantIso: represents,
          dataSourceNoteZh: weatherSnap.dataSourceNoteZh,
        );
      }

      // 單日 forecast 無資料時改試歷史網格（僅天氣，浪況常缺）
      final arch = await _getJson(
        Uri.https("archive-api.open-meteo.com", "/v1/archive", {
          "latitude": "$lat",
          "longitude": "$lng",
          "hourly":
              "temperature_2m,relative_humidity_2m,weather_code,precipitation,rain,wind_speed_10m,wind_direction_10m",
          "timezone": "Asia/Taipei",
          "wind_speed_unit": "kmh",
          "start_date": ymd,
          "end_date": ymd,
        }),
      );
      if (arch != null) {
        final hw = arch["hourly"] as Map<String, dynamic>?;
        return _snapshotFromHourlyWeather(
              hw,
              when,
              moon,
              tideNote,
              represents,
              "指定時間（歷史網格／浪況可能無資料）",
            ) ??
            SpotEnvironmentSnapshot(
              moonPhaseZh: moon,
              tideNoteZh: tideNote,
              marineAvailable: false,
              representsInstantIso: represents,
              dataSourceNoteZh: "無法取得該時段資料",
              errorMessage: "該日期無 hourly 資料",
            );
      }

      return SpotEnvironmentSnapshot(
        moonPhaseZh: moon,
        tideNoteZh: tideNote,
        marineAvailable: false,
        representsInstantIso: represents,
        dataSourceNoteZh: "查詢失敗",
        errorMessage: "無法向 Open-Meteo 取得該日資料（日期過遠或服務限制）",
      );
    } catch (e) {
      return SpotEnvironmentSnapshot(
        moonPhaseZh: moon,
        tideNoteZh: tideNote,
        marineAvailable: false,
        representsInstantIso: represents,
        errorMessage: "$e",
      );
    }
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 14));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  SpotEnvironmentSnapshot? _snapshotFromHourlyWeather(
    Map<String, dynamic>? hourly,
    DateTime when,
    String moon,
    String tideNote,
    String representsIso,
    String sourceZh,
  ) {
    final idx = _nearestHourlyIndex(hourly?["time"], when);
    if (idx == null) return null;
    final wc = _hourlyInt(hourly, "weather_code", idx);
    final wdir = _hourlyDouble(hourly, "wind_direction_10m", idx);

    return SpotEnvironmentSnapshot(
      moonPhaseZh: moon,
      tideNoteZh: tideNote,
      tempC: _hourlyDouble(hourly, "temperature_2m", idx),
      humidityPct: _hourlyDouble(hourly, "relative_humidity_2m", idx),
      windKmh: _hourlyDouble(hourly, "wind_speed_10m", idx),
      windDirZh: direction16Zh(wdir),
      gustKmh: _hourlyDouble(hourly, "wind_gusts_10m", idx),
      precipitationMm: _hourlyDouble(hourly, "precipitation", idx),
      rainMm: _hourlyDouble(hourly, "rain", idx),
      weatherLabelZh: wc != null ? _wmoWeatherZh(wc) : null,
      marineAvailable: false,
      errorMessage: null,
      representsInstantIso: representsIso,
      dataSourceNoteZh: sourceZh,
    );
  }

  int? _nearestHourlyIndex(dynamic timeArr, DateTime when) {
    if (timeArr is! List || timeArr.isEmpty) return null;
    var bestI = 0;
    Duration bestDiff = const Duration(days: 99999);
    for (var i = 0; i < timeArr.length; i++) {
      final s = timeArr[i];
      if (s is! String) continue;
      final t = DateTime.tryParse(s);
      if (t == null) continue;
      final d = t.difference(when).abs();
      if (d < bestDiff) {
        bestDiff = d;
        bestI = i;
      }
    }
    return bestI;
  }

  double? _hourlyDouble(Map<String, dynamic>? h, String key, int i) {
    final list = h?[key];
    if (list is! List || i >= list.length) return null;
    final v = list[i];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return null;
  }

  int? _hourlyInt(Map<String, dynamic>? h, String key, int i) {
    final list = h?[key];
    if (list is! List || i >= list.length) return null;
    final v = list[i];
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  Future<SpotEnvironmentSnapshot> _fetchCurrent({
    required double lat,
    required double lng,
    required String moon,
    required String tideNote,
    String? representsInstantIso,
    String? dataSourceNoteZh,
  }) async {
    final weatherUri = Uri.https("api.open-meteo.com", "/v1/forecast", {
      "latitude": "$lat",
      "longitude": "$lng",
      "current":
          "temperature_2m,relative_humidity_2m,weather_code,precipitation,rain,wind_speed_10m,wind_direction_10m,wind_gusts_10m",
      "timezone": "Asia/Taipei",
      "wind_speed_unit": "kmh",
    });

    final marineUri = Uri.https("marine-api.open-meteo.com", "/v1/marine", {
      "latitude": "$lat",
      "longitude": "$lng",
      "current": "wave_height,wave_direction,wave_period,sea_surface_temperature",
      "timezone": "Asia/Taipei",
    });

    try {
      final wRes = await http.get(weatherUri).timeout(const Duration(seconds: 12));
      if (wRes.statusCode != 200) {
        return SpotEnvironmentSnapshot(
          moonPhaseZh: moon,
          tideNoteZh: tideNote,
          errorMessage: "天氣服務回應 ${wRes.statusCode}",
          representsInstantIso: representsInstantIso,
          dataSourceNoteZh: dataSourceNoteZh,
        );
      }
      final wj = jsonDecode(wRes.body) as Map<String, dynamic>;
      final cur = wj["current"] as Map<String, dynamic>?;
      double? gv(Map<String, dynamic>? m, String k) {
        final v = m?[k];
        if (v is num) return v.toDouble();
        return null;
      }

      int? wi(Map<String, dynamic>? m, String k) {
        final v = m?[k];
        if (v is int) return v;
        if (v is num) return v.toInt();
        return null;
      }

      final weatherCode = wi(cur, "weather_code");

      http.Response? mRes;
      try {
        mRes = await http.get(marineUri).timeout(const Duration(seconds: 12));
      } catch (_) {
        mRes = null;
      }

      double? wh;
      String? wdz;
      double? wp;
      double? sst;
      var marineOk = false;

      if (mRes != null && mRes.statusCode == 200) {
        final mj = jsonDecode(mRes.body) as Map<String, dynamic>;
        final mc = mj["current"] as Map<String, dynamic>?;
        if (mc != null) {
          marineOk = true;
          wh = gv(mc, "wave_height");
          final wd = gv(mc, "wave_direction");
          wdz = direction16Zh(wd);
          wp = gv(mc, "wave_period");
          sst = gv(mc, "sea_surface_temperature");
        }
      }

      final wdir = gv(cur, "wind_direction_10m");

      return SpotEnvironmentSnapshot(
        moonPhaseZh: moon,
        tideNoteZh: tideNote,
        tempC: gv(cur, "temperature_2m"),
        humidityPct: gv(cur, "relative_humidity_2m"),
        windKmh: gv(cur, "wind_speed_10m"),
        windDirZh: direction16Zh(wdir),
        gustKmh: gv(cur, "wind_gusts_10m"),
        precipitationMm: gv(cur, "precipitation"),
        rainMm: gv(cur, "rain"),
        weatherLabelZh: weatherCode != null ? _wmoWeatherZh(weatherCode) : null,
        waveHeightM: wh,
        waveDirZh: wdz,
        wavePeriodS: wp,
        seaSurfaceTempC: sst,
        marineAvailable: marineOk,
        representsInstantIso: representsInstantIso,
        dataSourceNoteZh: dataSourceNoteZh,
      );
    } catch (e) {
      return SpotEnvironmentSnapshot(
        moonPhaseZh: moon,
        tideNoteZh: tideNote,
        errorMessage: "$e",
        representsInstantIso: representsInstantIso,
        dataSourceNoteZh: dataSourceNoteZh,
      );
    }
  }

  /// 發文流程用：擷取「此刻」並標記為發文紀錄。
  Future<SpotEnvironmentSnapshot> fetchAtPostTime({
    required double lat,
    required double lng,
  }) async {
    final t = DateTime.now();
    final snap = await _fetchCurrent(
      lat: lat,
      lng: lng,
      moon: moonPhaseLabelZh(t),
      tideNote: SpotEnvironmentSnapshot.tideHintZh,
      representsInstantIso: t.toUtc().toIso8601String(),
      dataSourceNoteZh: "發文當下擷取",
    );
    return snap;
  }
}
