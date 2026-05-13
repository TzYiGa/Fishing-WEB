import "package:fishing_map/config/map_tokens.dart";
import "package:fishing_map/models/cwa_station_kind.dart";
import "package:fishing_map/models/cwa_station_point.dart";
import "package:fishing_map/models/fishing_spot.dart";
import "package:fishing_map/models/spot_category.dart";
import "package:fishing_map/models/spot_entry_kind.dart";
import "package:fishing_map/models/map_view_settings.dart";
import "package:fishing_map/widgets/cwa_map_marker_assets.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_map/flutter_map.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:latlong2/latlong.dart";
import "package:fishing_map/widgets/mapbox_web_canvas_stub.dart"
    if (dart.library.html) "package:fishing_map/widgets/mapbox_web_canvas_web.dart";

class FishingMapView extends StatelessWidget {
  const FishingMapView({
    super.key,
    required this.spots,
    this.cwaStations = const [],
    this.showCwaTide = true,
    this.showCwaBuoy = true,
    this.showOceanFlow = false,
    this.oceanFlowGeoJsonT0 = '{"type":"FeatureCollection","features":[]}',
    this.oceanFlowGeoJsonT1 = "",
    this.oceanFlowDataTau = 0,
    required this.pickMode,
    required this.mapController,
    required this.onTapAt,
    required this.onSpotTap,
    required this.settingsListenable,
  });

  /// 使用者必須在新增釣點流程中才可點選地圖取點。
  final bool pickMode;

  final List<FishingSpot> spots;
  final List<CwaStationPoint> cwaStations;
  final bool showCwaTide;
  final bool showCwaBuoy;
  /// Web Mapbox：WINDY SPEC v2 拉格朗日粒子流（非 Web 忽略）。
  final bool showOceanFlow;
  final String oceanFlowGeoJsonT0;
  final String oceanFlowGeoJsonT1;
  final double oceanFlowDataTau;
  final MapController mapController;
  final void Function(LatLng latLng) onTapAt;
  final void Function(FishingSpot spot) onSpotTap;
  final ValueListenable<MapViewSettings> settingsListenable;

  static const LatLng _defaultCenter = LatLng(23.7, 121.0);

  @override
  Widget build(BuildContext context) {
    if (mapboxAccessToken.isEmpty) {
      return const _TokenMissing();
    }

    return ValueListenableBuilder<MapViewSettings>(
      valueListenable: settingsListenable,
      builder: (context, settings, _) {
        final styleId = "mapbox/${settings.style.mapboxStyleId}";
        final urlTemplate =
            "https://api.mapbox.com/styles/v1/$styleId/tiles/256/{z}/{x}/{y}@2x?access_token=$mapboxAccessToken";

        if (kIsWeb) {
          // 潮位／浮標開關由 MapboxWebCanvas.didUpdateWidget → fishingMapUpdate 只改圖層 visibility，勿加會改 key 的 Widget，否則每次切換都會整張地圖重建。
          return MapboxWebCanvas(
            spots: spots,
            cwaStations: cwaStations,
            showCwaTide: showCwaTide,
            showCwaBuoy: showCwaBuoy,
            showFlowLayer: showOceanFlow,
            flowGeoJsonT0: oceanFlowGeoJsonT0,
            flowGeoJsonT1: oceanFlowGeoJsonT1,
            flowDataTau: oceanFlowDataTau,
            pickMode: pickMode,
            styleId: styleId,
            languageField: settings.language.mapboxNameField,
            accessToken: mapboxAccessToken,
            onTapAt: (lng, lat) => onTapAt(LatLng(lat, lng)),
            onSpotTap: (spotId) {
              final needle = spotId.trim();
              for (final spot in spots) {
                if (spot.id == needle) {
                  onSpotTap(spot);
                  return;
                }
              }
            },
          );
        }

        return FlutterMap(
          key: ValueKey(urlTemplate),
          mapController: mapController,
          options: MapOptions(
            initialCenter: _defaultCenter,
            initialZoom: 7.2,
            minZoom: 3,
            maxZoom: 18,
            onTap: (tapPos, latlng) {
              if (!pickMode) return;
              onTapAt(latlng);
            },
          ),
          children: [
            TileLayer(
              key: ValueKey("tile:$urlTemplate"),
              urlTemplate: urlTemplate,
              userAgentPackageName: "com.fishingmap.app",
            ),
            if (showCwaTide)
              MarkerLayer(
                markers: [
                  for (final c in cwaStations.where(
                    (p) => p.kind == CwaStationKind.tide,
                  ))
                    Marker(
                      point: LatLng(c.lat, c.lng),
                      width: 28,
                      height: 28,
                      child: SvgPicture.asset(
                        CwaMapMarkerAssets.tideSvg,
                        width: 28,
                        height: 28,
                        fit: BoxFit.contain,
                      ),
                    ),
                ],
              ),
            if (showCwaBuoy)
              MarkerLayer(
                markers: [
                  for (final c in cwaStations.where(
                    (p) => p.kind == CwaStationKind.buoy,
                  ))
                    Marker(
                      point: LatLng(c.lat, c.lng),
                      width: 28,
                      height: 28,
                      child: SvgPicture.asset(
                        CwaMapMarkerAssets.buoySvg,
                        width: 28,
                        height: 28,
                        fit: BoxFit.contain,
                      ),
                    ),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final s in spots)
                  Marker(
                    point: LatLng(s.lat, s.lng),
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () => onSpotTap(s),
                      child: Icon(
                        s.entryKind == SpotEntryKind.fishingPoi
                            ? Icons.flag_circle_rounded
                            : Icons.photo_camera_rounded,
                        color: spotCategoryMapMarkerColor(s.categoryId),
                        size: 40,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _TokenMissing extends StatelessWidget {
  const _TokenMissing();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.key_off_rounded,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(
                "未設定 Mapbox Token",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                "建置／執行時請加上 dart-define：\n"
                "flutter run -d chrome --dart-define=MAPBOX_ACCESS_TOKEN=你的pkToken",
              ),
            ],
          ),
        ),
      ),
    );
  }
}
