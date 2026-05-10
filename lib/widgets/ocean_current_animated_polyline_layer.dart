import "package:fishing_map/utils/ocean_current_polylines.dart";
import "package:flutter/material.dart";
import "package:flutter/scheduler.dart";
import "package:flutter_map/flutter_map.dart";

/// 海流折線層：以 [Ticker] 驅動行進虛線（非 Web／flutter_map）。
class OceanCurrentAnimatedPolylineLayer extends StatefulWidget {
  const OceanCurrentAnimatedPolylineLayer({
    super.key,
    required this.geoJson,
  });

  final String geoJson;

  @override
  State<OceanCurrentAnimatedPolylineLayer> createState() =>
      _OceanCurrentAnimatedPolylineLayerState();
}

class _OceanCurrentAnimatedPolylineLayerState
    extends State<OceanCurrentAnimatedPolylineLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _phase = 0;
  int _lastBucket = -1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final bucket = elapsed.inMilliseconds ~/ 26;
      if (bucket != _lastBucket) {
        _lastBucket = bucket;
        setState(() => _phase = bucket % 256);
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PolylineLayer(
      polylines: oceanCurrentMarchingPolylinesFromGeoJson(
        widget.geoJson,
        phase: _phase,
        stepsPerSegment: 16,
        patternPeriod: 5,
        patternOn: 2,
      ),
    );
  }
}
