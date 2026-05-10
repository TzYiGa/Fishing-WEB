import "dart:convert";
import "dart:js_interop";
import "dart:js_util" as js_util;
import "dart:ui_web" as ui_web;

import "package:fishing_map/models/cwa_station_point.dart";
import "package:fishing_map/models/fishing_spot.dart";
import "package:fishing_map/widgets/mapbox_interaction_overlay.dart";
import "package:flutter/material.dart";
import "package:web/web.dart" as web;

/// 潮位／浮標顯示各傳 1／0（勿用 bool）：Web 上 dart:js_interop 布林有時無法正確送到 JS。
@JS("fishingMapCreate")
external void _fishingMapCreate(
  String containerId,
  String accessToken,
  String styleId,
  String languageField,
  String spotsJson,
  String cwaStationsJson,
  int showCwaTideLayer,
  int showCwaBuoyLayer,
  int showOceanCurrentLayer,
  String oceanCurrentGeoJson,
  JSFunction onMapClick,
  JSFunction onSpotClick,
);

@JS("fishingMapUpdate")
external void _fishingMapUpdate(
  String containerId,
  String styleId,
  String languageField,
  String spotsJson,
  String cwaStationsJson,
  int showCwaTideLayer,
  int showCwaBuoyLayer,
  int showOceanCurrentLayer,
  String oceanCurrentGeoJson,
);

@JS("fishingMapDispose")
external void _fishingMapDispose(String containerId);

class MapboxWebCanvas extends StatefulWidget {
  const MapboxWebCanvas({
    super.key,
    required this.spots,
    this.cwaStations = const [],
    this.showCwaTide = true,
    this.showCwaBuoy = true,
    this.showOceanCurrent = false,
    this.oceanCurrentGeoJson = '{"type":"FeatureCollection","features":[]}',
    required this.pickMode,
    required this.styleId,
    required this.languageField,
    required this.accessToken,
    required this.onTapAt,
    required this.onSpotTap,
  });

  final List<FishingSpot> spots;
  /// 中央氣象署海象／潮位等測站（與釣點分層）。
  final List<CwaStationPoint> cwaStations;
  final bool showCwaTide;
  final bool showCwaBuoy;
  final bool showOceanCurrent;
  final String oceanCurrentGeoJson;
  final bool pickMode;
  final String styleId;
  final String languageField;
  final String accessToken;
  final void Function(double lng, double lat) onTapAt;
  final void Function(String spotId) onSpotTap;

  @override
  State<MapboxWebCanvas> createState() => _MapboxWebCanvasState();
}

class _MapboxWebCanvasState extends State<MapboxWebCanvas> {
  late final String _containerId;
  late final String _viewType;
  bool _created = false;

  @override
  void initState() {
    super.initState();
    _containerId = "fishing-map-${DateTime.now().microsecondsSinceEpoch}";
    _viewType = "fishing-map-view-$_containerId";

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final div = web.HTMLDivElement()
        ..id = _containerId
        ..style.width = "100%"
        ..style.height = "100%";
      return div;
    });

    // 再等一幀：釣點已 preload + watchSpots 首期事件後，widget.spots 才穩定，
    // 且 HtmlElementView DOM 較常晚一幀掛上（否則 fishingMapUpdate 可能早於 maps 註冊）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _createMap();
      });
    });
  }

  @override
  void didUpdateWidget(covariant MapboxWebCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_created) return;
    final spotsChanged =
        _spotsJson(oldWidget.spots) != _spotsJson(widget.spots);
    final cwaChanged =
        _cwaJson(oldWidget.cwaStations) != _cwaJson(widget.cwaStations) ||
            oldWidget.showCwaTide != widget.showCwaTide ||
            oldWidget.showCwaBuoy != widget.showCwaBuoy;
    final oceanChanged =
        oldWidget.showOceanCurrent != widget.showOceanCurrent ||
        oldWidget.oceanCurrentGeoJson != widget.oceanCurrentGeoJson;
    if (oldWidget.styleId != widget.styleId ||
        oldWidget.languageField != widget.languageField ||
        spotsChanged ||
        cwaChanged ||
        oceanChanged) {
      _updateMap();
    }
  }

  @override
  void dispose() {
    if (_created) {
      _fishingMapDispose(_containerId);
    }
    super.dispose();
  }

  void _createMap() {
    final spotsJson = _spotsJson(widget.spots);
    final onMapClick = ((double lng, double lat) {
      if (!widget.pickMode) return;
      widget.onTapAt(lng, lat);
    }).toJS;
    final onSpotClick = ((String spotId) {
      widget.onSpotTap(spotId);
    }).toJS;

    _fishingMapCreate(
      _containerId,
      widget.accessToken,
      widget.styleId,
      widget.languageField,
      spotsJson,
      _cwaJson(widget.cwaStations),
      widget.showCwaTide ? 1 : 0,
      widget.showCwaBuoy ? 1 : 0,
      widget.showOceanCurrent ? 1 : 0,
      widget.oceanCurrentGeoJson,
      onMapClick,
      onSpotClick,
    );
    _created = true;
    // 若先前開過底表把 handlers 設成停用，新建的 map 也會繼承全地圖停用狀態；建立後依阻擋深度同步。
    setMapboxInteractionsEnabledGlobally(true);
  }

  void _updateMap() {
    _fishingMapUpdate(
      _containerId,
      widget.styleId,
      widget.languageField,
      _spotsJson(widget.spots),
      _cwaJson(widget.cwaStations),
      widget.showCwaTide ? 1 : 0,
      widget.showCwaBuoy ? 1 : 0,
      widget.showOceanCurrent ? 1 : 0,
      widget.oceanCurrentGeoJson,
    );
  }

  String _spotsJson(List<FishingSpot> spots) {
    return jsonEncode([
      for (final s in spots)
        {
          "id": s.id,
          "lat": s.lat,
          "lng": s.lng,
          "category": s.categoryId,
        },
    ]);
  }

  String _cwaJson(List<CwaStationPoint> stations) {
    return jsonEncode([for (final p in stations) p.toJson()]);
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
