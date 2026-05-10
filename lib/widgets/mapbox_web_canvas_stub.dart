import "package:fishing_map/models/cwa_station_point.dart";
import "package:fishing_map/models/fishing_spot.dart";
import "package:flutter/material.dart";

class MapboxWebCanvas extends StatelessWidget {
  const MapboxWebCanvas({
    super.key,
    required this.spots,
    this.cwaStations = const [],
    this.showCwaTide = true,
    this.showCwaBuoy = true,
    this.showFlowLayer = false,
    this.flowGeoJsonT0 = '{"type":"FeatureCollection","features":[]}',
    this.flowGeoJsonT1 = "",
    this.flowDataTau = 0,
    required this.pickMode,
    required this.styleId,
    required this.languageField,
    required this.accessToken,
    required this.onTapAt,
    required this.onSpotTap,
  });

  final List<FishingSpot> spots;
  final List<CwaStationPoint> cwaStations;
  final bool showCwaTide;
  final bool showCwaBuoy;
  final bool showFlowLayer;
  final String flowGeoJsonT0;
  final String flowGeoJsonT1;
  final double flowDataTau;
  final bool pickMode;
  final String styleId;
  final String languageField;
  final String accessToken;
  final void Function(double lng, double lat) onTapAt;
  final void Function(String spotId) onSpotTap;

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text("Mapbox web canvas is only available on web."));
  }
}
