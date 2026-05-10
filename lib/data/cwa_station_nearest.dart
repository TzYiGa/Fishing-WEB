import "package:fishing_map/models/cwa_station_kind.dart";
import "package:fishing_map/models/cwa_station_point.dart";
import "package:latlong2/latlong.dart";

/// 自 [stations]（通常為 `StationID.json`）找出與 (lat, lng) 距離最短之測站。
///
/// 僅考慮 [CwaStationPoint.isMappableKind] 為 true 之點（潮位／浮標），
/// 與地圖兩類圖層一致；若皆無則回傳 null。
CwaStationPoint? findNearestCwaStation(
  double lat,
  double lng,
  List<CwaStationPoint> stations,
) {
  final usable =
      stations.where((s) => s.isMappableKind).toList(growable: false);
  if (usable.isEmpty) return null;
  const distance = Distance();
  var bestM = double.infinity;
  CwaStationPoint? best;
  final here = LatLng(lat, lng);
  for (final s in usable) {
    final m = distance(here, LatLng(s.lat, s.lng));
    if (m < bestM) {
      bestM = m;
      best = s;
    }
  }
  return best;
}

/// 與 [kind] 相同之測站中距離 (lat, lng) 最近者；無則 null。
CwaStationPoint? findNearestCwaStationOfKind(
  double lat,
  double lng,
  List<CwaStationPoint> stations,
  CwaStationKind kind,
) {
  final usable = stations.where((s) => s.kind == kind).toList(growable: false);
  if (usable.isEmpty) return null;
  const distance = Distance();
  var bestM = double.infinity;
  CwaStationPoint? best;
  final here = LatLng(lat, lng);
  for (final s in usable) {
    final m = distance(here, LatLng(s.lat, s.lng));
    if (m < bestM) {
      bestM = m;
      best = s;
    }
  }
  return best;
}