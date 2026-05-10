import "dart:convert";

import "package:fishing_map/models/cwa_station_kind.dart";
import "package:fishing_map/models/cwa_station_point.dart";
import "package:flutter/services.dart";

/// 自資產 [StationID.json] 解析 `SeaSurfaceObs.Location` 內之測站座標。
Future<List<CwaStationPoint>> loadCwaStationPointsFromAsset() async {
  final raw = await rootBundle.loadString("StationID.json");
  final root = jsonDecode(raw);
  if (root is! Map) return const [];

  final locations = _extractLocations(root);
  final out = <CwaStationPoint>[];
  for (var i = 0; i < locations.length; i++) {
    final loc = locations[i];
    final st = _asStringKeyedMap(loc["Station"] ?? loc["station"]);
    if (st == null) continue;
    final idRaw =
        "${st["StationID"] ?? st["stationID"] ?? ""}".trim();
    final name =
        "${st["StationName"] ?? st["stationName"] ?? idRaw}".trim();
    final la = double.tryParse(
      "${st["StationLatitude"] ?? st["stationLatitude"] ?? ""}",
    );
    final lo = double.tryParse(
      "${st["StationLongitude"] ?? st["stationLongitude"] ?? ""}",
    );
    if (la == null || lo == null) continue;
    if (la.isNaN || lo.isNaN) continue;
    final id = idRaw.isEmpty ? "cwa-$i" : idRaw;
    final attrZh =
        "${st["StationAttribute"] ?? st["stationAttribute"] ?? ""}".trim();
    final attrEn =
        "${st["StationAttributeEN"] ?? st["stationAttributeEN"] ?? ""}".trim();
    final k = _classifyKind(attrZh, attrEn);
    out.add(
      CwaStationPoint(
        id: id,
        name: name.isEmpty ? id : name,
        lat: la,
        lng: lo,
        kind: k,
      ),
    );
  }
  return out;
}

/// 依 `StationAttribute` 分潮位站 vs 浮標／浮球（其餘為 [CwaStationKind.other]）。
CwaStationKind _classifyKind(String attrZh, String attrEn) {
  final blob = "${attrZh.toLowerCase()} ${attrEn.toLowerCase()}";
  if (blob.contains("潮位") || blob.contains("tidal")) {
    return CwaStationKind.tide;
  }
  if (blob.contains("浮球") ||
      blob.contains("浮標") ||
      blob.contains("buoy")) {
    return CwaStationKind.buoy;
  }
  return CwaStationKind.other;
}

List<dynamic> _extractLocations(Map<dynamic, dynamic> root) {
  final op = root["cwaopendata"] ?? root["Cwaopendata"];
  if (op is! Map) return const [];
  final resources = op["Resources"] ?? op["resources"];
  if (resources is! Map) return const [];
  final resource = resources["Resource"] ?? resources["resource"];
  final maps = <Map<dynamic, dynamic>>[];
  if (resource is List) {
    for (final r in resource) {
      if (r is Map) maps.add(r);
    }
  } else if (resource is Map) {
    maps.add(resource);
  }
  final all = <dynamic>[];
  for (final rm in maps) {
    final data = rm["Data"] ?? rm["data"];
    if (data is! Map) continue;
    final sso = data["SeaSurfaceObs"] ?? data["seaSurfaceObs"];
    if (sso is! Map) continue;
    final loc = sso["Location"] ?? sso["location"];
    if (loc is List) all.addAll(loc);
  }
  return all;
}

Map<String, dynamic>? _asStringKeyedMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    return Map<String, dynamic>.from(
      v.map((k, x) => MapEntry("$k", x)),
    );
  }
  return null;
}
