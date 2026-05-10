(function () {
  const maps = {};
  /** containerId → 最近一次釣點（地圖尚未註冊到 maps[] 時，update 不能只 return） */
  const pendingSpotUpdates = {};
  /** 與 pendingSpotUpdates 並行：地圖建立前就送達的測站圖層設定 */
  const pendingCwaStore = {};
  /** 地圖建立前送達的海流 GeoJSON／開關 */
  const pendingOceanStore = {};

  /**
   * 海流「沿向量流動」動畫：底層 ocean-current-lines 為依流速著色實線（資料驅動），
   * 上層 ocean-current-flow 為純色虛線，只動 line-dashoffset，避免 dash 與 step 顏色同層不相容。
   */
  var oceanFlowAnimRaf = null;
  var oceanFlowPhase = 0;

  function scheduleOceanFlowAnimation() {
    if (oceanFlowAnimRaf != null) return;
    oceanFlowAnimRaf = requestAnimationFrame(tickOceanFlowAnim);
  }

  function tickOceanFlowAnim() {
    oceanFlowAnimRaf = null;
    var needNext = false;
    oceanFlowPhase += 1.35;
    var off = -(oceanFlowPhase % 36);
    var pulse = 0.58 + 0.36 * Math.sin(oceanFlowPhase * 0.14);
    for (const cid of Object.keys(maps)) {
      const it = maps[cid];
      if (!it || !it.showOceanCurrent) continue;
      const m = it.map;
      if (!m || typeof m.getLayer !== "function") continue;
      if (m.getLayer("ocean-current-flow")) {
        try {
          m.setPaintProperty("ocean-current-flow", "line-dashoffset", off);
          needNext = true;
        } catch (_) {}
      }
      if (m.getLayer("ocean-current-arrows")) {
        try {
          m.setPaintProperty("ocean-current-arrows", "icon-opacity", pulse);
          needNext = true;
        } catch (_) {}
      }
    }
    if (needNext) {
      oceanFlowAnimRaf = requestAnimationFrame(tickOceanFlowAnim);
    }
  }

  function stopOceanFlowAnimation() {
    if (oceanFlowAnimRaf != null) {
      cancelAnimationFrame(oceanFlowAnimRaf);
      oceanFlowAnimRaf = null;
    }
  }

  function getStyleUrl(styleId) {
    if (!styleId) return "mapbox://styles/mapbox/outdoors-v12";
    if (styleId.startsWith("mapbox://")) return styleId;
    return `mapbox://styles/${styleId}`;
  }

  /** 與 Flutter `assets/cwa/cwa_tide_marker.svg` 內容一致；fetch 失敗時內嵌使用。 */
  const CWA_TIDE_MARKER_SVG_FALLBACK =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">' +
    '<circle cx="16" cy="16" r="14" fill="#ffffff" stroke="#7dd3fc" stroke-width="1.15"/>' +
    '<path fill="#0284c7" stroke="#0369a1" stroke-width="0.45" stroke-linejoin="round" d="M16 9.2c-3.45 3.05-5.75 6-5.75 9.45 0 3.18 2.58 5.75 5.75 5.75s5.75-2.57 5.75-5.75c0-3.45-2.3-6.4-5.75-9.45z"/>' +
    '<path fill="#ffffff" fill-opacity="0.48" d="M16 11.5c-1.9 1.45-3.05 3.05-3.05 4.8 0 1.68 1.36 3.05 3.05 3.05s3.05-1.37 3.05-3.05c0-1.75-1.15-3.35-3.05-4.8z"/>' +
    '</svg>';

  /** 與 Flutter `assets/cwa/cwa_buoy_marker.svg` 內容一致；fetch 失敗時內嵌使用。 */
  const CWA_BUOY_MARKER_SVG_FALLBACK =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">' +
    '<circle cx="16" cy="16" r="14" fill="#fffbeb" stroke="#fdba74" stroke-width="1.1"/>' +
    '<ellipse cx="16" cy="19.6" rx="7.2" ry="4.6" fill="#9a3412"/>' +
    '<ellipse cx="16" cy="19.35" rx="6.85" ry="4.25" fill="#D84315" stroke="#c2410c" stroke-width="0.55"/>' +
    '<ellipse cx="16" cy="18.05" rx="5.15" ry="2.2" fill="#fb923c" fill-opacity="0.9"/>' +
    '<rect x="14.75" y="8.2" width="2.5" height="9.2" rx="1.25" fill="#7c2d12"/>' +
    '<rect x="14.95" y="8.35" width="2.1" height="8.9" rx="1.05" fill="#9a3412"/>' +
    '<circle cx="16" cy="7.35" r="1.55" fill="#fb923c" stroke="#c2410c" stroke-width="0.45"/>' +
    '</svg>';

  /**
   * 釣點與 CWA 測站叢集共用：合併半徑（畫素）、超過此 zoom 後改為單點。
   */
  const SPOT_CLUSTER_MAX_ZOOM = 13;
  const SPOT_CLUSTER_RADIUS = 26;

  function getLanguageExpression(languageField) {
    return ["coalesce", ["get", languageField], ["get", "name"]];
  }

  function expressionContainsNameField(expr) {
    if (expr == null) return false;
    if (typeof expr === "string") {
      return (
        expr.includes("{name}") ||
        expr.includes("{name_") ||
        expr === "name" ||
        expr.startsWith("name_")
      );
    }
    if (!Array.isArray(expr)) return false;
    for (const item of expr) {
      if (expressionContainsNameField(item)) return true;
    }
    return false;
  }

  function isRoadShieldLayer(layerId) {
    const id = (layerId || "").toLowerCase();
    return (
      id.includes("road-number") ||
      id.includes("road_number") ||
      id.includes("shield") ||
      id.includes("motorway") ||
      id.includes("route-number") ||
      id.includes("route_number")
    );
  }

  function applyLanguage(map, languageField) {
    const style = map.getStyle();
    if (!style || !style.layers) return;
    for (const layer of style.layers) {
      if (layer.type !== "symbol") continue;
      if (layer.id === "spots-cluster-count") continue;
      if (
        layer.id === "cwa-tide-label" ||
        layer.id === "cwa-buoy-label" ||
        layer.id === "cwa-tide-icon" ||
        layer.id === "cwa-buoy-icon" ||
        layer.id === "cwa-tide-unclustered" ||
        layer.id === "cwa-buoy-unclustered" ||
        layer.id === "cwa-tide-cluster-count" ||
        layer.id === "cwa-buoy-cluster-count"
      )
        continue;
      if (layer.id === "cwa-stations-label") continue;
      if (layer.id === "ocean-current-arrows") continue;
      if (isRoadShieldLayer(layer.id)) continue;
      try {
        const textField = map.getLayoutProperty(layer.id, "text-field");
        if (textField == null) continue;
        if (!expressionContainsNameField(textField)) continue;
        map.setLayoutProperty(layer.id, "text-field", getLanguageExpression(languageField));
      } catch (_) {}
    }
  }

  function toFeatureCollection(spots) {
    return {
      type: "FeatureCollection",
      features: (spots || []).map((s) => ({
        type: "Feature",
        geometry: {
          type: "Point",
          coordinates: [s.lng, s.lat],
        },
        properties: {
          id: String(s.id),
          category: String(s.category != null && s.category !== "" ? s.category : "1-2"),
        },
      })),
    };
  }

  function cwaPointFeature(s) {
    return {
      type: "Feature",
      geometry: {
        type: "Point",
        coordinates: [Number(s.lng), Number(s.lat)],
      },
      properties: {
        id: String(s.id != null ? s.id : ""),
        name: String(s.name != null ? s.name : ""),
      },
    };
  }

  /** 拆成潮位／浮標兩份，各用獨立叢集來源（與釣點相同 clusterMaxZoom／clusterRadius）。 */
  function toCwaSplitCollections(stations) {
    const list = stations || [];
    const tide = [];
    const buoy = [];
    for (var i = 0; i < list.length; i++) {
      const s = list[i];
      if (s.kind === "tide") tide.push(cwaPointFeature(s));
      else if (s.kind === "buoy") buoy.push(cwaPointFeature(s));
    }
    return {
      tide: { type: "FeatureCollection", features: tide },
      buoy: { type: "FeatureCollection", features: buoy },
    };
  }

  /** 與釣點 [spotsSourceSpec] 相同之 clusterMaxZoom／clusterRadius。 */
  function cwaStationsClusterSourceSpec(data) {
    return {
      type: "geojson",
      data,
      cluster: true,
      clusterMaxZoom: SPOT_CLUSTER_MAX_ZOOM,
      clusterRadius: SPOT_CLUSTER_RADIUS,
      clusterMinPoints: 2,
    };
  }

  function removeLegacyCwaCircleLayers(map) {
    for (const lid of ["cwa-tide-circle", "cwa-buoy-circle"]) {
      if (map.getLayer(lid)) {
        try {
          map.removeLayer(lid);
        } catch (_) {}
      }
    }
  }

  /** 移除舊版平面 cwa-stations 或先前圖層 id，再建叢集版。 */
  function removeOldCwaStationStack(map) {
    const layerIds = [
      "cwa-buoy-label",
      "cwa-buoy-unclustered",
      "cwa-buoy-cluster-count",
      "cwa-buoy-clusters",
      "cwa-tide-label",
      "cwa-tide-unclustered",
      "cwa-tide-cluster-count",
      "cwa-tide-clusters",
      "cwa-buoy-icon",
      "cwa-tide-icon",
      "cwa-buoy-circle",
      "cwa-tide-circle",
    ];
    for (var i = 0; i < layerIds.length; i++) {
      const lid = layerIds[i];
      if (map.getLayer(lid)) {
        try {
          map.removeLayer(lid);
        } catch (_) {}
      }
    }
    const srcIds = ["cwa-stations", "cwa-tide-stations", "cwa-buoy-stations"];
    for (var j = 0; j < srcIds.length; j++) {
      const sid = srcIds[j];
      if (map.getSource(sid)) {
        try {
          map.removeSource(sid);
        } catch (_) {}
      }
    }
  }

  function setCwaClusterLayerVisibility(map, visTide, visBuoy) {
    const tide = [
      "cwa-tide-clusters",
      "cwa-tide-cluster-count",
      "cwa-tide-unclustered",
      "cwa-tide-label",
    ];
    const buoy = [
      "cwa-buoy-clusters",
      "cwa-buoy-cluster-count",
      "cwa-buoy-unclustered",
      "cwa-buoy-label",
    ];
    for (var a = 0; a < tide.length; a++) {
      const lid = tide[a];
      if (map.getLayer(lid)) {
        map.setLayoutProperty(lid, "visibility", visTide);
      }
    }
    for (var b = 0; b < buoy.length; b++) {
      const lidB = buoy[b];
      if (map.getLayer(lidB)) {
        map.setLayoutProperty(lidB, "visibility", visBuoy);
      }
    }
  }

  function addCwaTideClusterLayers(map) {
    if (!map.getLayer("cwa-tide-clusters")) {
      map.addLayer({
        id: "cwa-tide-clusters",
        type: "circle",
        source: "cwa-tide-stations",
        filter: ["has", "point_count"],
        paint: {
          "circle-color": [
            "step",
            ["get", "point_count"],
            "#7dd3fc",
            10,
            "#38bdf8",
            50,
            "#0284c7",
          ],
          "circle-radius": [
            "step",
            ["get", "point_count"],
            11,
            10,
            14,
            50,
            17,
          ],
          "circle-stroke-width": 1.5,
          "circle-stroke-color": "#ffffff",
        },
      });
    }
    if (!map.getLayer("cwa-tide-cluster-count")) {
      map.addLayer({
        id: "cwa-tide-cluster-count",
        type: "symbol",
        source: "cwa-tide-stations",
        filter: ["has", "point_count"],
        layout: {
          "text-field": ["to-string", ["get", "point_count"]],
          "text-font": ["DIN Offc Pro Medium", "Arial Unicode MS Bold"],
          "text-size": 11,
        },
        paint: {
          "text-color": "#0c4a6e",
        },
      });
    }
    if (!map.getLayer("cwa-tide-unclustered")) {
      map.addLayer({
        id: "cwa-tide-unclustered",
        type: "symbol",
        source: "cwa-tide-stations",
        filter: ["!", ["has", "point_count"]],
        layout: {
          "icon-image": "cwa-tide-marker",
          "icon-size": 0.52,
          "icon-allow-overlap": true,
          "icon-ignore-placement": false,
        },
      });
    }
    if (!map.getLayer("cwa-tide-label")) {
      map.addLayer({
        id: "cwa-tide-label",
        type: "symbol",
        source: "cwa-tide-stations",
        filter: ["!", ["has", "point_count"]],
        minzoom: 10,
        layout: {
          "text-field": ["coalesce", ["get", "name"], ["get", "id"]],
          "text-size": 10,
          "text-offset": [0, 1.35],
          "text-anchor": "top",
          "text-font": ["DIN Offc Pro Medium", "Arial Unicode MS Bold"],
        },
        paint: {
          "text-color": "#0369a1",
          "text-halo-color": "#ffffff",
          "text-halo-width": 1,
        },
      });
    }
  }

  function addCwaBuoyClusterLayers(map) {
    if (!map.getLayer("cwa-buoy-clusters")) {
      map.addLayer({
        id: "cwa-buoy-clusters",
        type: "circle",
        source: "cwa-buoy-stations",
        filter: ["has", "point_count"],
        paint: {
          "circle-color": [
            "step",
            ["get", "point_count"],
            "#fdba74",
            10,
            "#fb923c",
            50,
            "#ea580c",
          ],
          "circle-radius": [
            "step",
            ["get", "point_count"],
            11,
            10,
            14,
            50,
            17,
          ],
          "circle-stroke-width": 1.5,
          "circle-stroke-color": "#ffffff",
        },
      });
    }
    if (!map.getLayer("cwa-buoy-cluster-count")) {
      map.addLayer({
        id: "cwa-buoy-cluster-count",
        type: "symbol",
        source: "cwa-buoy-stations",
        filter: ["has", "point_count"],
        layout: {
          "text-field": ["to-string", ["get", "point_count"]],
          "text-font": ["DIN Offc Pro Medium", "Arial Unicode MS Bold"],
          "text-size": 11,
        },
        paint: {
          "text-color": "#7c2d12",
        },
      });
    }
    if (!map.getLayer("cwa-buoy-unclustered")) {
      map.addLayer({
        id: "cwa-buoy-unclustered",
        type: "symbol",
        source: "cwa-buoy-stations",
        filter: ["!", ["has", "point_count"]],
        layout: {
          "icon-image": "cwa-buoy-marker",
          "icon-size": 0.52,
          "icon-allow-overlap": true,
          "icon-ignore-placement": false,
        },
      });
    }
    if (!map.getLayer("cwa-buoy-label")) {
      map.addLayer({
        id: "cwa-buoy-label",
        type: "symbol",
        source: "cwa-buoy-stations",
        filter: ["!", ["has", "point_count"]],
        minzoom: 10,
        layout: {
          "text-field": ["coalesce", ["get", "name"], ["get", "id"]],
          "text-size": 10,
          "text-offset": [0, 1.35],
          "text-anchor": "top",
          "text-font": ["DIN Offc Pro Medium", "Arial Unicode MS Bold"],
        },
        paint: {
          "text-color": "#9a3412",
          "text-halo-color": "#ffffff",
          "text-halo-width": 1,
        },
      });
    }
  }

  /** 優先 fetch 與 Flutter 相同之 `assets/cwa/*.svg`，失敗則用內嵌 fallback（Mapbox 需先 addImage）。 */
  function ensureCwaMarkerImagesLoaded(map, done) {
    if (map.hasImage("cwa-tide-marker") && map.hasImage("cwa-buoy-marker")) {
      done();
      return;
    }
    var pending = 2;
    function oneDone() {
      pending--;
      if (pending <= 0) done();
    }
    function loadSvgAsset(id, relUrl, fallbackSvg) {
      if (map.hasImage(id)) {
        oneDone();
        return;
      }
      function applySvgText(svgText) {
        var img = new Image(72, 72);
        img.onload = function () {
          try {
            if (!map.hasImage(id)) map.addImage(id, img, { pixelRatio: 2 });
          } catch (_) {}
          oneDone();
        };
        img.onerror = function () {
          oneDone();
        };
        img.src =
          "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svgText);
      }
      fetch(relUrl)
        .then(function (r) {
          if (!r.ok) throw new Error("cwa svg " + r.status);
          return r.text();
        })
        .then(applySvgText)
        .catch(function () {
          applySvgText(fallbackSvg);
        });
    }
    loadSvgAsset(
      "cwa-tide-marker",
      "assets/cwa/cwa_tide_marker.svg",
      CWA_TIDE_MARKER_SVG_FALLBACK,
    );
    loadSvgAsset(
      "cwa-buoy-marker",
      "assets/cwa/cwa_buoy_marker.svg",
      CWA_BUOY_MARKER_SVG_FALLBACK,
    );
  }

  /** 潮位站／浮標站：與釣點相同參數之叢集 + 單點圖示／文字（置於 spots 底層）。 */
  function ensureCwaStationLayers(map, item) {
    const split = toCwaSplitCollections(item.cwaData);
    const visTide = item.showCwaTide ? "visible" : "none";
    const visBuoy = item.showCwaBuoy ? "visible" : "none";

    function syncCwaLayers() {
      removeLegacyCwaCircleLayers(map);
      const needBuild = !map.getSource("cwa-tide-stations");
      if (needBuild) {
        removeOldCwaStationStack(map);
        map.addSource(
          "cwa-tide-stations",
          cwaStationsClusterSourceSpec(split.tide),
        );
        map.addSource(
          "cwa-buoy-stations",
          cwaStationsClusterSourceSpec(split.buoy),
        );
        addCwaTideClusterLayers(map);
        addCwaBuoyClusterLayers(map);
      } else {
        const st = map.getSource("cwa-tide-stations");
        if (st && typeof st.setData === "function") {
          st.setData(split.tide);
        }
        const sb = map.getSource("cwa-buoy-stations");
        if (sb && typeof sb.setData === "function") {
          sb.setData(split.buoy);
        }
      }
      setCwaClusterLayerVisibility(map, visTide, visBuoy);
    }

    ensureCwaMarkerImagesLoaded(map, syncCwaLayers);
  }

  function parseShowCwaFlag(v) {
    if (v === false || v === "false") return false;
    const n = Number(v);
    if (!Number.isNaN(n) && n === 0) return false;
    if (v === "0") return false;
    return true;
  }

  function parseOceanFeatureCollectionJson(s) {
    try {
      if (s != null && typeof s === "object") {
        if (s.type === "FeatureCollection" && Array.isArray(s.features)) return s;
      }
      const txt = typeof s === "string" ? s : JSON.stringify(s ?? {});
      const o = JSON.parse(txt || "{}");
      if (o && o.type === "FeatureCollection" && Array.isArray(o.features)) return o;
    } catch (_) {}
    return { type: "FeatureCollection", features: [] };
  }

  /** 與 `lib/utils/ocean_current_polylines.dart` 分級一致（流速為 km/h，來自 u/v 換算）。 */
  function oceanCurrentLineColorStep() {
    return [
      "step",
      ["coalesce", ["to-number", ["get", "speed"]], 0],
      "#E0F2FE",
      0.5,
      "#7DD3FC",
      2,
      "#0284C7",
      4,
      "#F59E0B",
      8,
      "#B91C1C",
    ];
  }

  /** 由線段終點＋ bearing 產生箭頭用 Point 圖層（與線向量同向）。 */
  function buildOceanArrowPointFc(fc) {
    const feats = [];
    const list = (fc && fc.features) || [];
    for (var i = 0; i < list.length; i++) {
      const f = list[i];
      if (!f || !f.geometry || f.geometry.type !== "LineString") continue;
      const c = f.geometry.coordinates;
      if (!c || c.length < 2) continue;
      const end = c[c.length - 1];
      const p = f.properties || {};
      var br = p.bearing != null ? Number(p.bearing) : NaN;
      if (Number.isNaN(br)) br = 0;
      feats.push({
        type: "Feature",
        geometry: { type: "Point", coordinates: [end[0], end[1]] },
        properties: {
          bearing: br,
          speed: p.speed != null ? p.speed : 0,
        },
      });
    }
    return { type: "FeatureCollection", features: feats };
  }

  /** 箭頭圖示（尖端朝北），以 icon-rotate = bearing 對齊海流向量。 */
  function ensureOceanArrowImageLoaded(map, onDone) {
    if (map.hasImage("ocean-flow-arrow")) {
      onDone();
      return;
    }
    var canvas =
      typeof document !== "undefined" && document.createElement
        ? document.createElement("canvas")
        : null;
    if (!canvas) {
      onDone();
      return;
    }
    var w = 56;
    var h = 56;
    canvas.width = w;
    canvas.height = h;
    var ctx = canvas.getContext("2d");
    if (!ctx) {
      onDone();
      return;
    }
    ctx.clearRect(0, 0, w, h);
    ctx.translate(w / 2, h / 2);
    ctx.fillStyle = "rgba(255,255,255,0.96)";
    ctx.strokeStyle = "rgba(2,132,199,0.75)";
    ctx.lineWidth = 1.8;
    ctx.beginPath();
    ctx.moveTo(0, -20);
    ctx.lineTo(13, 16);
    ctx.lineTo(-13, 16);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    var img = new Image();
    img.onload = function () {
      try {
        if (!map.hasImage("ocean-flow-arrow")) {
          map.addImage("ocean-flow-arrow", img, { pixelRatio: 2 });
        }
      } catch (_) {}
      onDone();
    };
    img.onerror = function () {
      onDone();
    };
    img.src = canvas.toDataURL("image/png");
  }

  /** 表層海流線＋流向箭頭＋虛線流動；箭頭在釣點圖層之下。 */
  function ensureOceanCurrentLayers(map, item) {
    const vis = item.showOceanCurrent ? "visible" : "none";
    const fc = parseOceanFeatureCollectionJson(item.oceanCurrentGeoJson);
    const arrowFc = buildOceanArrowPointFc(fc);

    if (!map.getSource("ocean-current")) {
      try {
        map.addSource("ocean-current", { type: "geojson", data: fc });
      } catch (_) {}
    } else {
      const st = map.getSource("ocean-current");
      if (st && typeof st.setData === "function") {
        try {
          st.setData(fc);
        } catch (_) {}
      }
    }

    if (!map.getSource("ocean-current-arrows")) {
      try {
        map.addSource("ocean-current-arrows", { type: "geojson", data: arrowFc });
      } catch (_) {}
    } else {
      const sa = map.getSource("ocean-current-arrows");
      if (sa && typeof sa.setData === "function") {
        try {
          sa.setData(arrowFc);
        } catch (_) {}
      }
    }

    if (!map.getLayer("ocean-current-lines")) {
      try {
        map.addLayer({
          id: "ocean-current-lines",
          type: "line",
          source: "ocean-current",
          layout: { visibility: vis },
          paint: {
            "line-color": oceanCurrentLineColorStep(),
            "line-width": 2.6,
            "line-opacity": 0.94,
            "line-cap": "round",
            "line-join": "round",
          },
        });
      } catch (_) {}
    } else {
      try {
        map.setLayoutProperty("ocean-current-lines", "visibility", vis);
      } catch (_) {}
    }
    if (!map.getLayer("ocean-current-flow")) {
      try {
        map.addLayer({
          id: "ocean-current-flow",
          type: "line",
          source: "ocean-current",
          layout: { visibility: vis },
          paint: {
            "line-color": "rgba(255,255,255,0.72)",
            "line-width": 2.2,
            "line-opacity": 0.95,
            "line-cap": "round",
            "line-join": "round",
            "line-dasharray": [1.2, 2.2],
            "line-dashoffset": 0,
          },
        });
      } catch (_) {}
    } else {
      try {
        map.setLayoutProperty("ocean-current-flow", "visibility", vis);
        map.setPaintProperty("ocean-current-flow", "line-dasharray", [1.2, 2.2]);
      } catch (_) {}
    }

    requestAnimationFrame(function () {
      scheduleOceanFlowAnimation();
    });

    ensureOceanArrowImageLoaded(map, function () {
      if (!map.getLayer("ocean-current-arrows")) {
        try {
          map.addLayer({
            id: "ocean-current-arrows",
            type: "symbol",
            source: "ocean-current-arrows",
            layout: {
              visibility: vis,
              "icon-image": "ocean-flow-arrow",
              "icon-rotate": ["get", "bearing"],
              "icon-rotation-alignment": "map",
              "icon-pitch-alignment": "map",
              "icon-allow-overlap": true,
              "icon-ignore-placement": true,
              "icon-size": [
                "interpolate",
                ["linear"],
                ["coalesce", ["to-number", ["get", "speed"]], 0],
                0.08,
                0.22,
                0.6,
                0.34,
                2,
                0.46,
                6,
                0.58,
              ],
            },
            paint: {
              "icon-opacity": 0.88,
            },
          });
        } catch (_) {}
      } else {
        try {
          map.setLayoutProperty("ocean-current-arrows", "visibility", vis);
        } catch (_) {}
      }
      try {
        if (map.getLayer("ocean-current-arrows") && map.getLayer("spots-clusters")) {
          map.moveLayer("ocean-current-arrows", "spots-clusters");
        }
      } catch (_) {}
      requestAnimationFrame(function () {
        scheduleOceanFlowAnimation();
      });
    });
  }

  /** 與 Dart `categoryId`（1-1 … 2-3）對應的單點顏色；叢集仍用上方藍階。 */
  function unclusteredCircleColorMatch() {
    return [
      "match",
      ["get", "category"],
      "1-1",
      "#075985",
      "1-2",
      "#0284c7",
      "1-3",
      "#0d9488",
      "1-4",
      "#0369a1",
      "2-1",
      "#15803d",
      "2-2",
      "#16a34a",
      "2-3",
      "#22c55e",
      "#94a3b8",
    ];
  }

  function spotsSourceSpec(data) {
    return {
      type: "geojson",
      data,
      cluster: true,
      clusterMaxZoom: SPOT_CLUSTER_MAX_ZOOM,
      clusterRadius: SPOT_CLUSTER_RADIUS,
      clusterMinPoints: 2,
    };
  }

  /** 建立／補齊叢集圓＋數字＋單點圖層，並置於最上層。 */
  function ensureSpotClusterLayers(map) {
    if (!map.getLayer("spots-clusters")) {
      map.addLayer({
        id: "spots-clusters",
        type: "circle",
        source: "spots",
        filter: ["has", "point_count"],
        paint: {
          "circle-color": [
            "step",
            ["get", "point_count"],
            "#0284c7",
            10,
            "#0369a1",
            50,
            "#0c4a6e",
          ],
          "circle-radius": [
            "step",
            ["get", "point_count"],
            18,
            10,
            22,
            50,
            28,
          ],
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
        },
      });
    }
    if (!map.getLayer("spots-cluster-count")) {
      map.addLayer({
        id: "spots-cluster-count",
        type: "symbol",
        source: "spots",
        filter: ["has", "point_count"],
        layout: {
          "text-field": ["to-string", ["get", "point_count"]],
          "text-font": ["DIN Offc Pro Medium", "Arial Unicode MS Bold"],
          "text-size": 13,
        },
        paint: {
          "text-color": "#ffffff",
        },
      });
    }
    if (!map.getLayer("spots-unclustered")) {
      map.addLayer({
        id: "spots-unclustered",
        type: "circle",
        source: "spots",
        filter: ["!", ["has", "point_count"]],
        paint: {
          "circle-radius": 12,
          "circle-color": unclusteredCircleColorMatch(),
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
        },
      });
    }
    try {
      map.moveLayer("spots-clusters");
      map.moveLayer("spots-cluster-count");
      map.moveLayer("spots-unclustered");
    } catch (_) {}
  }

  function clickXY(e) {
    const p = e.point;
    if (Array.isArray(p)) return { x: p[0], y: p[1] };
    return { x: p.x, y: p.y };
  }

  function clusterSourceIdFromLayerId(layerId) {
    if (!layerId) return null;
    if (layerId.indexOf("cwa-tide") === 0) return "cwa-tide-stations";
    if (layerId.indexOf("cwa-buoy") === 0) return "cwa-buoy-stations";
    if (
      layerId.indexOf("spots-") === 0 ||
      layerId === "spots-unclustered" ||
      layerId === "spots-clusters" ||
      layerId === "spots-cluster-count"
    )
      return "spots";
    return null;
  }

  /** 優先釣點叢集／測站叢集與單點（v3 用 [[x1,y1],[x2,y2]] 畫素框）。 */
  function firstSpotHitFeatureAt(map, e) {
    const pad = 16;
    const { x, y } = clickXY(e);
    const box = [
      [x - pad, y - pad],
      [x + pad, y + pad],
    ];
    const layers = [
      "spots-cluster-count",
      "spots-unclustered",
      "spots-clusters",
      "cwa-tide-cluster-count",
      "cwa-tide-unclustered",
      "cwa-tide-clusters",
      "cwa-buoy-cluster-count",
      "cwa-buoy-unclustered",
      "cwa-buoy-clusters",
    ];
    const opts = { layers };
    let fs = map.queryRenderedFeatures(box, opts);
    if (fs && fs.length) return fs[0];
    fs = map.queryRenderedFeatures([x, y], opts);
    return fs && fs[0];
  }

  /** 必須在釣點圖層建立後呼叫；setStyle 後也要重綁。 */
  function wireMapClickHandlers(item) {
    const map = item.map;
    if (item._unifiedMapClick) {
      try {
        map.off("click", item._unifiedMapClick);
      } catch (_) {}
    }
    item._unifiedMapClick = (e) => {
      const f = firstSpotHitFeatureAt(map, e);
      const props = f && f.properties;
      if (props && props.point_count != null && props.cluster_id != null) {
        const lid = f.layer && f.layer.id;
        const srcId = clusterSourceIdFromLayerId(lid) || "spots";
        const src = map.getSource(srcId);
        if (
          src &&
          typeof src.getClusterExpansionZoom === "function" &&
          f.geometry &&
          f.geometry.coordinates
        ) {
          src.getClusterExpansionZoom(props.cluster_id, (err, zoom) => {
            if (err) return;
            map.easeTo({
              center: f.geometry.coordinates,
              zoom: zoom,
              duration: 400,
            });
          });
        }
        return;
      }
      const id = props && props.id;
      if (id != null && id !== "") {
        if (item.onSpotClick) item.onSpotClick(String(id));
        return;
      }
      if (item.onMapClick) item.onMapClick(e.lngLat.lng, e.lngLat.lat);
    };
    map.on("click", item._unifiedMapClick);
  }

  function createWhenReady(
    containerId,
    accessToken,
    styleId,
    languageField,
    spots,
    cwaStations,
    showCwaTide,
    showCwaBuoy,
    showOceanCurrent,
    oceanCurrentGeoJson,
    onMapClick,
    onSpotClick,
    attempts
  ) {
    const container = document.getElementById(containerId);
    if (!container) {
      if (attempts <= 0) return;
      setTimeout(
        () =>
          createWhenReady(
            containerId,
            accessToken,
            styleId,
            languageField,
            spots,
            cwaStations,
            showCwaTide,
            showCwaBuoy,
            showOceanCurrent,
            oceanCurrentGeoJson,
            onMapClick,
            onSpotClick,
            attempts - 1
          ),
        30
      );
      return;
    }

    mapboxgl.accessToken = accessToken;

    // DOM 準備較慢時會重試若幹次；在等待期間若 fishingMapUpdate 已先送達，
    // 會進 pendingSpotUpdates，這裡合併，避免永遠以建立時的空陣列當唯一資料。
    let mergedSpots = spots;
    if (pendingSpotUpdates[containerId]) {
      mergedSpots = pendingSpotUpdates[containerId];
      delete pendingSpotUpdates[containerId];
    }

    let mergedCwa = cwaStations;
    let mergedShowTide = parseShowCwaFlag(showCwaTide);
    let mergedShowBuoy = parseShowCwaFlag(showCwaBuoy);
    if (pendingCwaStore[containerId]) {
      mergedCwa = pendingCwaStore[containerId].stations;
      mergedShowTide = parseShowCwaFlag(pendingCwaStore[containerId].showTide);
      mergedShowBuoy = parseShowCwaFlag(pendingCwaStore[containerId].showBuoy);
      delete pendingCwaStore[containerId];
    }

    let mergedOceanShow = parseShowCwaFlag(showOceanCurrent);
    let mergedOceanJson =
      oceanCurrentGeoJson ||
      '{"type":"FeatureCollection","features":[]}';
    if (pendingOceanStore[containerId]) {
      mergedOceanShow = parseShowCwaFlag(pendingOceanStore[containerId].show);
      mergedOceanJson =
        pendingOceanStore[containerId].geoJson || mergedOceanJson;
      delete pendingOceanStore[containerId];
    }

    const map = new mapboxgl.Map({
      container: containerId,
      style: getStyleUrl(styleId),
      center: [121.0, 23.7],
      zoom: 7.2,
      minZoom: 3,
      maxZoom: 18,
    });

    // spotData：建立後、收到 fishingMapUpdate 時即可能更新；必須在 map「load」
    // 前寫入，否則 getSource('spots') 尚不存在會丟掉 setData（F5 後常只看到空標記）。
    const item = {
      map,
      onMapClick,
      onSpotClick,
      styleId,
      spotData: mergedSpots,
      cwaData: mergedCwa,
      showCwaTide: mergedShowTide,
      showCwaBuoy: mergedShowBuoy,
      showOceanCurrent: mergedOceanShow,
      oceanCurrentGeoJson: mergedOceanJson,
    };
    maps[containerId] = item;

    map.on("load", () => {
      applyLanguage(map, languageField);
      ensureOceanCurrentLayers(map, item);
      ensureCwaStationLayers(map, item);
      if (!map.getSource("spots")) {
        map.addSource(
          "spots",
          spotsSourceSpec(toFeatureCollection(item.spotData))
        );
      }
      ensureSpotClusterLayers(map);
      wireMapClickHandlers(item);
    });
  }

  window.fishingMapCreate = function (
    containerId,
    accessToken,
    styleId,
    languageField,
    spotsJson,
    cwaStationsJson,
    showCwaTideLayer,
    showCwaBuoyLayer,
    showOceanCurrentLayer,
    oceanCurrentGeoJson,
    onMapClick,
    onSpotClick
  ) {
    const spots = JSON.parse(spotsJson || "[]");
    const cwaStations = JSON.parse(cwaStationsJson || "[]");
    const showTide = parseShowCwaFlag(showCwaTideLayer);
    const showBuoy = parseShowCwaFlag(showCwaBuoyLayer);
    const showOcean = parseShowCwaFlag(showOceanCurrentLayer);
    const oceanJson =
      oceanCurrentGeoJson ||
      '{"type":"FeatureCollection","features":[]}';
    createWhenReady(
      containerId,
      accessToken,
      styleId,
      languageField,
      spots,
      cwaStations,
      showTide,
      showBuoy,
      showOcean,
      oceanJson,
      onMapClick,
      onSpotClick,
      30
    );
  };

  window.fishingMapUpdate = function (
    containerId,
    styleId,
    languageField,
    spotsJson,
    cwaStationsJson,
    showCwaTideLayer,
    showCwaBuoyLayer,
    showOceanCurrentLayer,
    oceanCurrentGeoJson
  ) {
    const spots = JSON.parse(spotsJson || "[]");
    const cwaStations = JSON.parse(cwaStationsJson || "[]");
    const showTide = parseShowCwaFlag(showCwaTideLayer);
    const showBuoy = parseShowCwaFlag(showCwaBuoyLayer);
    const showOcean = parseShowCwaFlag(showOceanCurrentLayer);
    const oceanJson =
      oceanCurrentGeoJson ||
      '{"type":"FeatureCollection","features":[]}';

    let item = maps[containerId];
    if (!item) {
      pendingSpotUpdates[containerId] = spots;
      pendingCwaStore[containerId] = {
        stations: cwaStations,
        showTide: showTide,
        showBuoy: showBuoy,
      };
      pendingOceanStore[containerId] = {
        show: showOcean,
        geoJson: oceanJson,
      };
      return;
    }
    const map = item.map;
    const nextStyle = getStyleUrl(styleId);
    item.spotData = spots;
    item.cwaData = cwaStations;
    item.showCwaTide = showTide;
    item.showCwaBuoy = showBuoy;
    item.showOceanCurrent = showOcean;
    item.oceanCurrentGeoJson = oceanJson;

    applyLanguage(map, languageField);

    const splitUp = toCwaSplitCollections(cwaStations);
    const cwaTideSrc = map.getSource("cwa-tide-stations");
    if (cwaTideSrc && typeof cwaTideSrc.setData === "function") {
      cwaTideSrc.setData(splitUp.tide);
    }
    const cwaBuoySrc = map.getSource("cwa-buoy-stations");
    if (cwaBuoySrc && typeof cwaBuoySrc.setData === "function") {
      cwaBuoySrc.setData(splitUp.buoy);
    }
    const visTide = showTide ? "visible" : "none";
    const visBuoy = showBuoy ? "visible" : "none";
    setCwaClusterLayerVisibility(map, visTide, visBuoy);
    // load 完成前就收到 update 時圖層可能尚未建立（或舊版平面／單 symbol 圖層）
    if (!map.getLayer("cwa-tide-unclustered") || !map.getLayer("cwa-buoy-unclustered")) {
      try {
        ensureCwaStationLayers(map, item);
      } catch (_) {}
    }

    const source = map.getSource("spots");
    if (source) {
      source.setData(toFeatureCollection(spots));
    }
    try {
      ensureOceanCurrentLayers(map, item);
    } catch (_) {}
    if (item.styleId !== styleId) {
      item.styleId = styleId;
      map.setStyle(nextStyle);
      // styledata 常過早；idle 確保可依賴 sources/layers API，並可重綁 click。
      map.once("idle", () => {
        if (!maps[containerId] || maps[containerId] !== item) return;
        applyLanguage(map, languageField);
        ensureOceanCurrentLayers(map, item);
        ensureCwaStationLayers(map, item);
        const src = map.getSource("spots");
        if (!src) {
          map.addSource(
            "spots",
            spotsSourceSpec(toFeatureCollection(item.spotData))
          );
        } else if (typeof src.setData === "function") {
          src.setData(toFeatureCollection(item.spotData));
        }
        ensureSpotClusterLayers(map);
        wireMapClickHandlers(item);
      });
    }
  };

  function setMapInteractions(map, enabled) {
    const on = !!enabled;
    const handlers = [
      "dragPan",
      "scrollZoom",
      "boxZoom",
      "dragRotate",
      "keyboard",
      "doubleClickZoom",
      "touchZoomRotate",
      "touchPitch",
    ];
    for (const name of handlers) {
      const h = map[name];
      if (!h || typeof h.enable !== "function" || typeof h.disable !== "function")
        continue;
      try {
        if (on) h.enable();
        else h.disable();
      } catch (_) {}
    }
  }

  /**
   * Flutter 打開留言／底表時設 false：僅關閉平移／縮放等 handlers。
   * 勿設 pointer-events:none——會讓標記點完全點不進去，且未關閉底表時易卡死。
   */
  window.fishingMapSetInteractionsEnabledAll = function (enabled) {
    const on = !!enabled;
    for (const id of Object.keys(maps)) {
      const m = maps[id] && maps[id].map;
      if (!m) continue;
      try {
        setMapInteractions(m, on);
      } catch (_) {}
    }
  };

  window.fishingMapDispose = function (containerId) {
    const item = maps[containerId];
    if (!item) return;
    stopOceanFlowAnimation();
    item.map.remove();
    delete maps[containerId];
    delete pendingSpotUpdates[containerId];
    delete pendingCwaStore[containerId];
    delete pendingOceanStore[containerId];
    requestAnimationFrame(function () {
      scheduleOceanFlowAnimation();
    });
  };
})();
