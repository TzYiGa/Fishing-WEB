import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter_map/flutter_map.dart";
import "package:latlong2/latlong.dart";

Color colorForOceanCurrentSpeedKmh(double s) {
  if (s < 0.5) return const Color(0xFFE0F2FE);
  if (s < 2) return const Color(0xFF7DD3FC);
  if (s < 4) return const Color(0xFF0284C7);
  if (s < 8) return const Color(0xFFF59E0B);
  return const Color(0xFFB91C1C);
}

/// 將 [CopernicusOceanVectorService] 產生之 GeoJSON 轉成 `flutter_map` 折線。
List<Polyline> oceanCurrentPolylinesFromGeoJson(String jsonStr) {
  try {
    final o = jsonDecode(jsonStr) as Map<String, dynamic>;
    final feats = o["features"] as List? ?? [];
    final out = <Polyline>[];
    for (final raw in feats) {
      if (raw is! Map<String, dynamic>) continue;
      final geom = raw["geometry"] as Map<String, dynamic>?;
      if (geom == null || geom["type"] != "LineString") continue;
      final coords = geom["coordinates"] as List?;
      if (coords == null || coords.length < 2) continue;
      final props = raw["properties"] as Map<String, dynamic>?;
      final spd = (props?["speed"] as num?)?.toDouble() ?? 0;
      final a = coords[0] as List;
      final b = coords[1] as List;
      if (a.length < 2 || b.length < 2) continue;
      final lng0 = (a[0] as num).toDouble();
      final lat0 = (a[1] as num).toDouble();
      final lng1 = (b[0] as num).toDouble();
      final lat1 = (b[1] as num).toDouble();
      out.add(
        Polyline(
          points: [
            LatLng(lat0, lng0),
            LatLng(lat1, lng1),
          ],
          color: colorForOceanCurrentSpeedKmh(spd),
          strokeWidth: 2,
        ),
      );
    }
    return out;
  } catch (_) {
    return [];
  }
}

/// 細分線段並依 [phase] 做行進虛線（供非 Web 之 `flutter_map` 動畫）。
List<Polyline> oceanCurrentMarchingPolylinesFromGeoJson(
  String jsonStr, {
  required int phase,
  int stepsPerSegment = 10,
  int patternPeriod = 6,
  int patternOn = 2,
}) {
  if (patternOn < 1 || patternOn >= patternPeriod) return oceanCurrentPolylinesFromGeoJson(jsonStr);
  try {
    final o = jsonDecode(jsonStr) as Map<String, dynamic>;
    final feats = o["features"] as List? ?? [];
    final out = <Polyline>[];
    for (final raw in feats) {
      if (raw is! Map<String, dynamic>) continue;
      final geom = raw["geometry"] as Map<String, dynamic>?;
      if (geom == null || geom["type"] != "LineString") continue;
      final coords = geom["coordinates"] as List?;
      if (coords == null || coords.length < 2) continue;
      final props = raw["properties"] as Map<String, dynamic>?;
      final spd = (props?["speed"] as num?)?.toDouble() ?? 0;
      final a = coords[0] as List;
      final b = coords[1] as List;
      if (a.length < 2 || b.length < 2) continue;
      final lng0 = (a[0] as num).toDouble();
      final lat0 = (a[1] as num).toDouble();
      final lng1 = (b[0] as num).toDouble();
      final lat1 = (b[1] as num).toDouble();
      final col = colorForOceanCurrentSpeedKmh(spd);
      final n = stepsPerSegment;
      for (var i = 0; i < n; i++) {
        if (((i + phase) % patternPeriod) >= patternOn) continue;
        final t0 = i / n;
        final t1 = (i + 1) / n;
        final latA = lat0 + (lat1 - lat0) * t0;
        final lngA = lng0 + (lng1 - lng0) * t0;
        final latB = lat0 + (lat1 - lat0) * t1;
        final lngB = lng0 + (lng1 - lng0) * t1;
        out.add(
          Polyline(
            points: [
              LatLng(latA, lngA),
              LatLng(latB, lngB),
            ],
            color: col,
            strokeWidth: 2.5,
          ),
        );
      }
    }
    return out;
  } catch (_) {
    return [];
  }
}
