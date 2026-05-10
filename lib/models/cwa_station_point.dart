import "package:fishing_map/models/cwa_station_kind.dart";

/// 中央氣象署開放資料（StationID.json）之海象觀測站點位，僅供地圖顯示用。
class CwaStationPoint {
  const CwaStationPoint({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.kind,
  });

  final String id;
  final String name;
  final double lat;
  final double lng;
  final CwaStationKind kind;

  /// 潮位／浮標兩類會畫在海象圖層；[CwaStationKind.other] 不畫。
  bool get isMappableKind =>
      kind == CwaStationKind.tide || kind == CwaStationKind.buoy;

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "lat": lat,
        "lng": lng,
        "kind": switch (kind) {
          CwaStationKind.tide => "tide",
          CwaStationKind.buoy => "buoy",
          CwaStationKind.other => "other",
        },
      };
}
