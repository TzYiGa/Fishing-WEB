import "dart:convert";
import "dart:math" as math;

import "package:flutter/services.dart";
import "package:http/http.dart" as http;

/// 由 Copernicus Marine（`uo`/`vo`）向量 JSON 產生 GeoJSON `LineString`
/// （Web Mapbox WINDY SPEC v2 粒子流場會讀取之速度／方位屬性）。
///
/// JSON 格式：`[{ "lat", "lng", "u", "v" }, ...]`（`u`/`v` 為 m/s，東向／北向）。
///
/// 資料來源（優先序）：
/// 1. 編譯參數 **`OCEAN_VECTORS_JSON_URL`** 非空時，執行期 `GET` 該 URL（便於 CI 更新後由 CDN／raw 提供最新檔）。
/// 2. 否則讀 **`assets/data/copernicus_ocean_vectors.json`**（可由本機腳本或 GitHub Actions 定期寫入）。
///
/// 自動化排程：`.github/workflows/update-copernicus-ocean-vectors.yml`
class CopernicusOceanVectorService {
  CopernicusOceanVectorService({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  static const String assetPath = "assets/data/copernicus_ocean_vectors.json";

  /// 若設定，[buildFeatureCollectionJson] 會優先向此 URL `GET`（失敗則退回 bundle）。
  static const String vectorsJsonUrlFromEnvironment = String.fromEnvironment(
    "OCEAN_VECTORS_JSON_URL",
    defaultValue: "",
  );

  static const String emptyFeatureCollectionJson =
      '{"type":"FeatureCollection","features":[]}';

  static const double _segmentKm = 3.2;
  static const double _minSpeedMs = 0.03;

  /// 讀取向量表（URL 或資產）並編成 GeoJSON 字串。
  Future<String> buildFeatureCollectionJson() async {
    final url = vectorsJsonUrlFromEnvironment.trim();
    if (url.isNotEmpty) {
      try {
        final res = await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 28));
        if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
          return _vectorsJsonToFeatureCollection(res.body);
        }
      } catch (_) {}
    }
    try {
      final raw = await rootBundle.loadString(assetPath);
      return _vectorsJsonToFeatureCollection(raw);
    } catch (_) {
      return emptyFeatureCollectionJson;
    }
  }

  static String _vectorsJsonToFeatureCollection(String raw) {
    try {
      final decoded = jsonDecode(raw);
      final list = decoded is List
          ? decoded
          : (decoded is Map<String, dynamic>
              ? (decoded["vectors"] as List? ?? const [])
              : const []);
      if (list.isEmpty) return emptyFeatureCollectionJson;

      final features = <Map<String, dynamic>>[];
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final lat = (item["lat"] as num?)?.toDouble();
        final lng = (item["lng"] as num?)?.toDouble();
        final u = (item["u"] as num?)?.toDouble();
        final v = (item["v"] as num?)?.toDouble();
        if (lat == null || lng == null || u == null || v == null) continue;
        final speedMs = math.sqrt(u * u + v * v);
        if (speedMs < _minSpeedMs) continue;
        final bearing = _bearingDegFromUV(u, v);
        final speedKmh = speedMs * 3.6;
        final end = _segmentEnd(lat, lng, bearing);
        features.add({
          "type": "Feature",
          "geometry": {
            "type": "LineString",
            "coordinates": [
              [lng, lat],
              [end.$2, end.$1],
            ],
          },
          "properties": {
            "speed": speedKmh,
            "bearing": bearing,
          },
        });
      }
      return jsonEncode({
        "type": "FeatureCollection",
        "features": features,
      });
    } catch (_) {
      return emptyFeatureCollectionJson;
    }
  }

  /// 流往方位角（度，自正北順時針），與 (u 東, v 北) 一致。
  static double _bearingDegFromUV(double u, double v) {
    final rad = math.atan2(u, v);
    var deg = rad * 180 / math.pi;
    while (deg < 0) {
      deg += 360;
    }
    while (deg >= 360) {
      deg -= 360;
    }
    return deg;
  }

  /// 回傳 (lat1, lng1)。
  static (double, double) _segmentEnd(double lat, double lng, double bearingDeg) {
    final br = bearingDeg * math.pi / 180;
    final dLat = (_segmentKm / 111.0) * math.cos(br);
    final dLng =
        (_segmentKm / (111.0 * math.cos(lat * math.pi / 180))) * math.sin(br);
    return (lat + dLat, lng + dLng);
  }
}
