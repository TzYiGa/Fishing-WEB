(function () {
  const maps = {};
  /** containerId → 最近一次釣點（地圖尚未註冊到 maps[] 時，update 不能只 return） */
  const pendingSpotUpdates = {};
  /** 與 pendingSpotUpdates 並行：地圖建立前就送達的測站圖層設定 */
  const pendingCwaStore = {};
  /** 地圖建立前送達的海流場（T0/T1 GeoJSON、τ、開關）— WINDY SPEC v2 */
  const pendingFlowStore = {};

  /** 管理員 DEBUG：`globalThis.fishingMapDartDebug(msg)` 由 Flutter 安裝（見 web_admin_debug_sink_web.dart）。 */
  function fmpDbg(msg) {
    try {
      var fn =
        typeof globalThis !== "undefined"
          ? globalThis.fishingMapDartDebug
          : null;
      if (typeof fn === "function") fn(String(msg));
    } catch (_) {}
  }

  /**
   * Flutter Web 的 HtmlElementView 外包 flt-platform-view 且常設 aria-hidden，
   * Mapbox canvas 卻會承接焦點，觸發「對焦祖先被 aria-hidden 隱藏」警告。
   * 於地圖載入後移除該 aria-hidden，並讓 canvas／容器以 tabindex=-1 離開 tab 鏈。
   */
  function patchMapboxFlutterPlatformViewA11y(map) {
    if (!map || typeof map.getContainer !== "function") return;
    try {
      if (typeof map.loaded === "function" && !map.loaded()) return;
    } catch (_) {
      return;
    }
    const root = map.getContainer();
    if (!root) return;
    try {
      let el = root.parentElement ? root.parentElement : null;
      while (el) {
        var tag = el.tagName && String(el.tagName).toUpperCase();
        if (tag === "FLT-PLATFORM-VIEW") {
          el.removeAttribute("aria-hidden");
          break;
        }
        el = el.parentElement;
      }
    } catch (_) {}
    try {
      if (typeof map.getCanvasContainer === "function") {
        const wrap = map.getCanvasContainer();
        if (wrap) {
          wrap.setAttribute("tabindex", "-1");
        }
      }
    } catch (_) {}
    try {
      var cv = typeof map.getCanvas === "function" ? map.getCanvas() : null;
      if (cv) {
        cv.setAttribute("tabindex", "-1");
      }
    } catch (_) {}
  }

  function getStyleUrl(styleId) {
    if (!styleId) return "mapbox://styles/mapbox/outdoors-v12";
    if (styleId.startsWith("mapbox://")) return styleId;
    return `mapbox://styles/${styleId}`;
  }

  /**
   * style 尚未 ready 時呼叫 getStyle/getLayer/getSource 會拋 "Style is not done loading"，
   * 錯誤傳回 Flutter Scheduler 易造成整頁白屏。
   */
  function runAfterMapStyleReady(map, fn) {
    if (!map || typeof fn !== "function") return;

    function attempt(isRetryIdle) {
      try {
        fn();
      } catch (e) {
        const msg = e && e.message ? String(e.message) : String(e || "");
        if (
          !isRetryIdle &&
          msg.indexOf("Style is not done loading") !== -1 &&
          typeof map.once === "function"
        ) {
          map.once("idle", function () {
            attempt(true);
          });
        }
      }
    }

    try {
      if (!map.loaded || typeof map.loaded !== "function" || !map.loaded()) {
        if (typeof map.once === "function") {
          map.once("load", function () {
            attempt(false);
          });
        }
        return;
      }
    } catch (_) {
      if (typeof map.once === "function") {
        map.once("load", function () {
          attempt(false);
        });
      }
      return;
    }
    attempt(false);
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
    try {
      if (!map.loaded || typeof map.loaded !== "function" || !map.loaded()) return;
    } catch (_) {
      return;
    }
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

  // ---------------------------------------------------------------------------
  // WINDY-STYLE FLOW RENDERER — PRODUCTION SPEC v2 (P1–P5, 3-clock, SoA, RK2)
  // ---------------------------------------------------------------------------
  const WF_GRID_N = 96;
  /** T_sim：固定物理步長（秒），以 CFL 子步滿足 |u|·dt / Δcell < 1 */
  const WF_DT_SIM = 1.72;
  const WF_PARTICLE_N = 840;
  const WF_REF_ZOOM = 7.5;
  const WF_FADE_ALPHA = 0.94;
  const WF_LINE_WIDTH = 1.05;
  const WF_SPEED_EPS = 0.025;
  const WF_MAX_AGE_BASE = 380;
  const WF_AGE_SPAN = 520;
  const WF_DBG_ARROWS = 1;
  const WF_DBG_TRACER = 2;
  const WF_DBG_GRID = 4;
  const WF_DBG_NO_FADE = 8;
  const WF_DBG_NEAREST = 16;

  function wfHashStr(s) {
    let h = 2166136261 >>> 0;
    const t = String(s || "");
    for (let i = 0; i < t.length; i++) {
      h ^= t.charCodeAt(i);
      h = Math.imul(h, 16777619) >>> 0;
    }
    return h >>> 0;
  }

  function wfMulberry32(seed) {
    let a = seed >>> 0;
    return function () {
      let t = (a += 0x6d2b79f5);
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function wfMetersPerDeg(latDeg) {
    const rad = (latDeg * Math.PI) / 180;
    const c = Math.cos(rad);
    return { mLat: 111320, mLng: 111320 * Math.max(1e-6, Math.abs(c)) };
  }

  function wfWrapLongitude(lng) {
    let x = lng;
    while (x > 180) x -= 360;
    while (x < -180) x += 360;
    return x;
  }

  function wfParseFeatureCollectionJson(txt) {
    try {
      const o = typeof txt === "string" ? JSON.parse(txt || "{}") : txt;
      if (o && o.type === "FeatureCollection" && Array.isArray(o.features)) return o;
    } catch (_) {}
    return { type: "FeatureCollection", features: [] };
  }

  function wfBearingUvFromProps(props) {
    const speedKmh = props.speed != null ? Number(props.speed) : NaN;
    const br = props.bearing != null ? Number(props.bearing) : NaN;
    if (Number.isNaN(speedKmh) || Number.isNaN(br)) return { u: NaN, v: NaN };
    const speedMs = speedKmh / 3.6;
    const brad = (br * Math.PI) / 180;
    return { u: speedMs * Math.sin(brad), v: speedMs * Math.cos(brad) };
  }

  function wfBuildUvDoubleGridFromFc(fc0, fc1) {
    const feats0 = fc0 && fc0.features ? fc0.features : [];
    let minLng = 180;
    let maxLng = -180;
    let minLat = 90;
    let maxLat = -90;
    for (let i = 0; i < feats0.length; i++) {
      const f = feats0[i];
      if (!f || !f.geometry || f.geometry.type !== "LineString") continue;
      const coords = f.geometry.coordinates;
      if (!coords || coords.length < 2) continue;
      for (const k of [0, coords.length - 1]) {
        const c = coords[k];
        const lg = Number(c[0]);
        const lt = Number(c[1]);
        if (Number.isNaN(lg) || Number.isNaN(lt)) continue;
        if (lg < minLng) minLng = lg;
        if (lg > maxLng) maxLng = lg;
        if (lt < minLat) minLat = lt;
        if (lt > maxLat) maxLat = lt;
      }
    }
    if (!(maxLng > minLng && maxLat > minLat)) return null;

    const padLng = (maxLng - minLng) * 0.08 + 0.02;
    const padLat = (maxLat - minLat) * 0.08 + 0.02;
    minLng -= padLng;
    maxLng += padLng;
    minLat -= padLat;
    maxLat += padLat;

    const nx = WF_GRID_N;
    const ny = WF_GRID_N;
    const nCell = nx * ny;

    function accumulate(fc, uSum, vSum, cnt) {
      const feats = fc && fc.features ? fc.features : [];
      for (let i = 0; i < feats.length; i++) {
        const f = feats[i];
        if (!f || !f.geometry || f.geometry.type !== "LineString") continue;
        const coords = f.geometry.coordinates;
        if (!coords || coords.length < 2) continue;
        const p = f.properties || {};
        const uv = wfBearingUvFromProps(p);
        if (Number.isNaN(uv.u)) continue;
        const a = coords[0];
        const b = coords[coords.length - 1];
        const lng0 = Number(a[0]);
        const lat0 = Number(a[1]);
        const lng1 = Number(b[0]);
        const lat1 = Number(b[1]);
        if ([lng0, lat0, lng1, lat1].some((x) => Number.isNaN(x))) continue;
        const geoDist = Math.hypot(lng1 - lng0, lat1 - lat0);
        const steps = Math.max(12, Math.min(100, Math.ceil(geoDist * 120)));
        for (let s = 0; s <= steps; s++) {
          const t = s / steps;
          const lng = lng0 + t * (lng1 - lng0);
          const lat = lat0 + t * (lat1 - lat0);
          let ix = Math.floor(((lng - minLng) / (maxLng - minLng)) * (nx - 0.001));
          let iy = Math.floor(((lat - minLat) / (maxLat - minLat)) * (ny - 0.001));
          if (ix < 0) ix = 0;
          if (iy < 0) iy = 0;
          if (ix >= nx) ix = nx - 1;
          if (iy >= ny) iy = ny - 1;
          const idx = iy * nx + ix;
          uSum[idx] += uv.u;
          vSum[idx] += uv.v;
          cnt[idx]++;
        }
      }
    }

    const u0 = new Float32Array(nCell);
    const v0 = new Float32Array(nCell);
    const u1 = new Float32Array(nCell);
    const v1 = new Float32Array(nCell);
    const c0 = new Int32Array(nCell);
    const c1 = new Int32Array(nCell);
    accumulate(fc0, u0, v0, c0);

    const f1 = fc1 && fc1.features && fc1.features.length ? fc1 : null;
    if (!f1) {
      for (let i = 0; i < nCell; i++) {
        u1[i] = u0[i];
        v1[i] = v0[i];
        c1[i] = c0[i];
      }
    } else {
      accumulate(f1, u1, v1, c1);
    }

    let vmax = 0;
    const midLat = (minLat + maxLat) * 0.5;
    const mp = wfMetersPerDeg(midLat);
    const cellMLat = ((maxLat - minLat) / Math.max(1, ny - 1)) * mp.mLat;
    const cellMLng = ((maxLng - minLng) / Math.max(1, nx - 1)) * mp.mLng;
    const minCellMeters = Math.min(cellMLat, cellMLng);

    for (let i = 0; i < nCell; i++) {
      if (c0[i] > 0) {
        u0[i] /= c0[i];
        v0[i] /= c0[i];
        const sp = Math.hypot(u0[i], v0[i]);
        if (sp > vmax) vmax = sp;
      } else {
        u0[i] = NaN;
        v0[i] = NaN;
      }
      if (c1[i] > 0) {
        u1[i] /= c1[i];
        v1[i] /= c1[i];
      } else {
        u1[i] = u0[i];
        v1[i] = v0[i];
      }
    }

    return {
      nx,
      ny,
      minLng,
      maxLng,
      minLat,
      maxLat,
      u0,
      v0,
      u1,
      v1,
      vmax,
      minCellMeters,
    };
  }

  function wfSampleUV(grid, lng, lat, tau, debugNearest) {
    if (
      lng < grid.minLng ||
      lng > grid.maxLng ||
      lat < grid.minLat ||
      lat > grid.maxLat
    ) {
      return { ok: false, u: 0, v: 0 };
    }
    const nx = grid.nx;
    const ny = grid.ny;
    const fx = ((lng - grid.minLng) / (grid.maxLng - grid.minLng)) * (nx - 1);
    const fy = ((lat - grid.minLat) / (grid.maxLat - grid.minLat)) * (ny - 1);

    function Uat(ix, iy) {
      const idx = iy * nx + ix;
      const a = grid.u0[idx];
      const b = grid.u1[idx];
      if (a !== a || b !== b) return NaN;
      return a + (b - a) * tau;
    }
    function Vat(ix, iy) {
      const idx = iy * nx + ix;
      const a = grid.v0[idx];
      const b = grid.v1[idx];
      if (a !== a || b !== b) return NaN;
      return a + (b - a) * tau;
    }

    if (debugNearest) {
      let ix = Math.round(fx);
      let iy = Math.round(fy);
      if (ix < 0) ix = 0;
      if (iy < 0) iy = 0;
      if (ix >= nx) ix = nx - 1;
      if (iy >= ny) iy = ny - 1;
      const u = Uat(ix, iy);
      const v = Vat(ix, iy);
      if (Number.isNaN(u) || Number.isNaN(v)) return { ok: false, u: 0, v: 0 };
      return { ok: true, u, v };
    }

    const ix0 = Math.floor(fx);
    const iy0 = Math.floor(fy);
    const ix1 = Math.min(nx - 1, ix0 + 1);
    const iy1 = Math.min(ny - 1, iy0 + 1);
    const tx = fx - ix0;
    const ty = fy - iy0;
    const w00 = (1 - tx) * (1 - ty);
    const w10 = tx * (1 - ty);
    const w01 = (1 - tx) * ty;
    const w11 = tx * ty;
    const u =
      w00 * Uat(ix0, iy0) +
      w10 * Uat(ix1, iy0) +
      w01 * Uat(ix0, iy1) +
      w11 * Uat(ix1, iy1);
    const v =
      w00 * Vat(ix0, iy0) +
      w10 * Vat(ix1, iy0) +
      w01 * Vat(ix0, iy1) +
      w11 * Vat(ix1, iy1);
    if (Number.isNaN(u) || Number.isNaN(v)) return { ok: false, u: 0, v: 0 };
    return { ok: true, u, v };
  }

  function wfBuildLutRgba() {
    const lut = new Uint8ClampedArray(256 * 4);
    for (let i = 0; i < 256; i++) {
      const t = i / 255;
      const r = 8 + t * 220;
      const g = 80 + t * 160;
      const b = 160 - t * 120;
      const r2 = Math.min(255, Math.max(0, r + t * 40));
      const g2 = Math.min(255, Math.max(0, g + t * 80));
      const b2 = Math.min(255, Math.max(0, b - t * 60));
      const a = 175 + Math.floor(t * 70);
      lut[i * 4] = r2 | 0;
      lut[i * 4 + 1] = g2 | 0;
      lut[i * 4 + 2] = b2 | 0;
      lut[i * 4 + 3] = a;
    }
    return lut;
  }

  const WF_LUT_RGBA = wfBuildLutRgba();

  function wfSpeedToLutIdx(speed) {
    const le = Math.log(speed + WF_SPEED_EPS);
    const lo = Math.log(WF_SPEED_EPS);
    const hi = Math.log(2.4);
    const t = (le - lo) / (hi - lo);
    return Math.floor(Math.min(1, Math.max(0, t)) * 255);
  }

  function wfZoomCompensation(map) {
    try {
      const z = map.getZoom();
      return Math.pow(2, WF_REF_ZOOM - z);
    } catch (_) {
      return 1;
    }
  }

  function wfOccupancyBins(grid, nBinX, nBinY) {
    return {
      nx: nBinX,
      ny: nBinY,
      minLng: grid.minLng,
      maxLng: grid.maxLng,
      minLat: grid.minLat,
      maxLat: grid.maxLat,
      counts: new Int32Array(nBinX * nBinY),
    };
  }

  function wfOccIndex(occ, lng, lat) {
    const fx = (lng - occ.minLng) / (occ.maxLng - occ.minLng);
    const fy = (lat - occ.minLat) / (occ.maxLat - occ.minLat);
    let ix = Math.floor(fx * occ.nx);
    let iy = Math.floor(fy * occ.ny);
    if (ix < 0) ix = 0;
    if (iy < 0) iy = 0;
    if (ix >= occ.nx) ix = occ.nx - 1;
    if (iy >= occ.ny) iy = occ.ny - 1;
    return iy * occ.nx + ix;
  }

  function wfRecomputeOcc(w) {
    const occ = w.occ;
    occ.counts.fill(0);
    const n = WF_PARTICLE_N;
    for (let i = 0; i < n; i++) {
      occ.counts[wfOccIndex(occ, w.lngs[i], w.lats[i])]++;
    }
  }

  function wfRespawnParticle(w, item, i) {
    const g = w.grid;
    const rng = w.rng;
    const tau = wfClampTau(item.flowDataTau);
    const dbgN = (w.debugMask & WF_DBG_NEAREST) !== 0;
    const occ = w.occ;
    let bestIdx = -1;
    let bestC = 1e9;
    for (let b = 0; b < occ.counts.length; b++) {
      if (occ.counts[b] < bestC) {
        bestC = occ.counts[b];
        bestIdx = b;
      }
    }
    for (let attempt = 0; attempt < 72; attempt++) {
      let lng;
      let lat;
      if (attempt < 36 && bestIdx >= 0) {
        const iy = Math.floor(bestIdx / occ.nx);
        const ix = bestIdx - iy * occ.nx;
        const t0 = rng();
        const t1 = rng();
        lng = occ.minLng + ((ix + t0) / occ.nx) * (occ.maxLng - occ.minLng);
        lat = occ.minLat + ((iy + t1) / occ.ny) * (occ.maxLat - occ.minLat);
      } else {
        lng = g.minLng + rng() * (g.maxLng - g.minLng);
        lat = g.minLat + rng() * (g.maxLat - g.minLat);
      }
      const s = wfSampleUV(g, lng, lat, tau, dbgN);
      if (s.ok) {
        w.lngs[i] = lng;
        w.lats[i] = lat;
        w.prev_lngs[i] = lng;
        w.prev_lats[i] = lat;
        w.ages[i] = rng() * WF_AGE_SPAN;
        w.max_ages[i] = WF_MAX_AGE_BASE + rng() * WF_AGE_SPAN;
        return;
      }
    }
  }

  function wfClampTau(t) {
    const x = Number(t);
    if (Number.isNaN(x)) return 0;
    if (x < 0) return 0;
    if (x > 1) return 1;
    return x;
  }

  function wfInitParticles(w, item) {
    const tau = wfClampTau(item.flowDataTau);
    const dbgN = (w.debugMask & WF_DBG_NEAREST) !== 0;
    for (let i = 0; i < WF_PARTICLE_N; i++) {
      wfRespawnParticle(w, item, i);
    }
    wfRecomputeOcc(w);
  }

  function wfStepParticle(w, item, i, dt, tau, zg, debugNearest) {
    const g = w.grid;
    const lngs = w.lngs;
    const lats = w.lats;
    const plng = w.prev_lngs;
    const plat = w.prev_lats;

    plng[i] = lngs[i];
    plat[i] = lats[i];

    const s0 = wfSampleUV(g, lngs[i], lats[i], tau, debugNearest);
    if (!s0.ok) {
      wfRespawnParticle(w, item, i);
      return;
    }

    const mp0 = wfMetersPerDeg(lats[i]);
    const u0s = s0.u * zg;
    const v0s = s0.v * zg;
    const k1_lng = (u0s / mp0.mLng) * dt;
    const k1_lat = (v0s / mp0.mLat) * dt;

    const mid_lng = lngs[i] + 0.5 * k1_lng;
    const mid_lat = lats[i] + 0.5 * k1_lat;

    const s1 = wfSampleUV(g, mid_lng, mid_lat, tau, debugNearest);
    if (!s1.ok) {
      lngs[i] = wfWrapLongitude(lngs[i] + k1_lng);
      lats[i] += k1_lat;
    } else {
      const mp1 = wfMetersPerDeg(mid_lat);
      const u1s = s1.u * zg;
      const v1s = s1.v * zg;
      lngs[i] = wfWrapLongitude(lngs[i] + (u1s / mp1.mLng) * dt);
      lats[i] += (v1s / mp1.mLat) * dt;
    }

    w.ages[i] += 1;
    if (w.ages[i] > w.max_ages[i]) {
      wfRespawnParticle(w, item, i);
    }
  }

  function wfAdvancePhysics(w, item, dtLogical, tau) {
    const map = item.map;
    const g = w.grid;
    const zgPhy = wfZoomCompensation(map);
    const vmax = g.vmax * zgPhy + WF_SPEED_EPS;
    const minCell = Math.max(g.minCellMeters, 1e-5);
    const dtSafe = (0.7 * minCell) / vmax;
    let nSub = 1;
    if (dtLogical > dtSafe && dtSafe > 1e-6) {
      nSub = Math.ceil(dtLogical / dtSafe);
      if (nSub > 64) nSub = 64;
    }
    const h = dtLogical / nSub;
    const dbgN = (w.debugMask & WF_DBG_NEAREST) !== 0;
    for (let s = 0; s < nSub; s++) {
      const zg = wfZoomCompensation(map);
      for (let i = 0; i < WF_PARTICLE_N; i++) {
        wfStepParticle(w, item, i, h, tau, zg, dbgN);
      }
    }
    if ((w.frameId & 7) === 0) wfRecomputeOcc(w);
    w.frameId++;
  }

  function wfDestroyFlowRenderer(item) {
    const wf = item._windyFlow;
    if (!wf) return;
    if (wf.raf != null) {
      try {
        cancelAnimationFrame(wf.raf);
      } catch (_) {}
      wf.raf = null;
    }
    const map = item.map;
    if (map && wf.onMoveStart) {
      try {
        map.off("movestart", wf.onMoveStart);
      } catch (_) {}
    }
    if (map && wf.onResize) {
      try {
        map.off("resize", wf.onResize);
      } catch (_) {}
    }
    if (wf.canvas && wf.canvas.parentNode) {
      try {
        wf.canvas.parentNode.removeChild(wf.canvas);
      } catch (_) {}
    }
    if (wf.dbgCanvas && wf.dbgCanvas.parentNode) {
      try {
        wf.dbgCanvas.parentNode.removeChild(wf.dbgCanvas);
      } catch (_) {}
    }
    item._windyFlow = null;
  }

  function wfSyncFlowCanvasSize(map, canvas) {
    const mc = map.getCanvas && map.getCanvas();
    if (!mc || !canvas) return;
    const w = Math.floor(mc.width);
    const h = Math.floor(mc.height);
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
    }
    const dpr = (typeof window !== "undefined" && window.devicePixelRatio) || 1;
    canvas.style.width = (mc.clientWidth || w / dpr) + "px";
    canvas.style.height = (mc.clientHeight || h / dpr) + "px";
  }

  function wfDrawDebugOverlays(w, item, map, ctxDbg) {
    const g = w.grid;
    const tau = wfClampTau(item.flowDataTau);
    const dbgN = (w.debugMask & WF_DBG_NEAREST) !== 0;
    if ((w.debugMask & WF_DBG_GRID) !== 0) {
      ctxDbg.save();
      ctxDbg.fillStyle = "rgba(250,204,21,0.35)";
      const step = 5;
      for (let iy = 0; iy < g.ny; iy += step) {
        for (let ix = 0; ix < g.nx; ix += step) {
          const fx = (ix / (g.nx - 1)) * (g.maxLng - g.minLng) + g.minLng;
          const fy = (iy / (g.ny - 1)) * (g.maxLat - g.minLat) + g.minLat;
          const s = wfSampleUV(g, fx, fy, tau, dbgN);
          if (!s.ok) continue;
          try {
            const p = map.project([fx, fy]);
            ctxDbg.beginPath();
            ctxDbg.arc(p.x, p.y, 2.2, 0, Math.PI * 2);
            ctxDbg.fill();
          } catch (_) {}
        }
      }
      ctxDbg.restore();
    }
    if ((w.debugMask & WF_DBG_ARROWS) !== 0) {
      ctxDbg.save();
      ctxDbg.strokeStyle = "rgba(251,191,36,0.85)";
      ctxDbg.lineWidth = 1.25;
      const stepA = 7;
      const dtArrow = 420;
      for (let iy = 0; iy < g.ny; iy += stepA) {
        for (let ix = 0; ix < g.nx; ix += stepA) {
          const lng = (ix / (g.nx - 1)) * (g.maxLng - g.minLng) + g.minLng;
          const lat = (iy / (g.ny - 1)) * (g.maxLat - g.minLat) + g.minLat;
          const s = wfSampleUV(g, lng, lat, tau, dbgN);
          if (!s.ok) continue;
          const mp = wfMetersPerDeg(lat);
          const dLng = (s.u * dtArrow) / mp.mLng;
          const dLat = (s.v * dtArrow) / mp.mLat;
          try {
            const p0 = map.project([lng, lat]);
            const p1 = map.project([lng + dLng, lat + dLat]);
            ctxDbg.beginPath();
            ctxDbg.moveTo(p0.x, p0.y);
            ctxDbg.lineTo(p1.x, p1.y);
            ctxDbg.stroke();
          } catch (_) {}
        }
      }
      ctxDbg.restore();
    }
  }

  function wfGridSignature(j0, j1) {
    return String(j0 || "") + "\n---T1---\n" + String(j1 || "");
  }

  function wfEnsureWindyFlow(item, map) {
    if (!item.showFlowLayer || !map) {
      fmpDbg(
        "[wfEnsureWindyFlow] skip showFlowLayer=" +
          String(item.showFlowLayer) +
          " hasMap=" +
          String(!!map)
      );
      wfDestroyFlowRenderer(item);
      return;
    }
    const fc0 = wfParseFeatureCollectionJson(item.flowGeoJsonT0);
    fmpDbg(
      "[wfEnsureWindyFlow] fc0.features.length=" +
        String(fc0.features ? fc0.features.length : 0)
    );
    if (!fc0.features || fc0.features.length === 0) {
      wfDestroyFlowRenderer(item);
      fmpDbg("[wfEnsureWindyFlow] destroy empty fc0");
      return;
    }
    const j1 = item.flowGeoJsonT1 && String(item.flowGeoJsonT1).trim() !== ""
      ? item.flowGeoJsonT1
      : item.flowGeoJsonT0;
    const fc1 = wfParseFeatureCollectionJson(j1);
    const sig = wfGridSignature(item.flowGeoJsonT0, j1);
    let wf = item._windyFlow;
    if (!wf || wf.gridSig !== sig) {
      wfDestroyFlowRenderer(item);
      const grid = wfBuildUvDoubleGridFromFc(fc0, fc1);
      if (!grid || grid.vmax < 1e-5) {
        fmpDbg(
          "[wfEnsureWindyFlow] no grid or vmax tiny grid=" +
            String(!!grid) +
            " vmax=" +
            String(grid ? grid.vmax : "n/a")
        );
        return;
      }
      fmpDbg("[wfEnsureWindyFlow] grid ok vmax=" + String(grid.vmax));
      const rng = wfMulberry32(wfHashStr(item.containerId) ^ wfHashStr(sig));
      wf = {
        grid,
        gridSig: sig,
        lngs: new Float32Array(WF_PARTICLE_N),
        lats: new Float32Array(WF_PARTICLE_N),
        prev_lngs: new Float32Array(WF_PARTICLE_N),
        prev_lats: new Float32Array(WF_PARTICLE_N),
        ages: new Float32Array(WF_PARTICLE_N),
        max_ages: new Float32Array(WF_PARTICLE_N),
        rng,
        occ: wfOccupancyBins(grid, 28, 22),
        simAccum: 0,
        lastTs: typeof performance !== "undefined" ? performance.now() : 0,
        raf: null,
        frameId: 0,
        canvas: null,
        dbgCanvas: null,
        debugMask: 0,
        onMoveStart: null,
        onResize: null,
      };
      wfInitParticles(wf, item);
      item._windyFlow = wf;
    }

    wf = item._windyFlow;
    if (!wf.canvas) {
      const c = document.createElement("canvas");
      c.style.position = "absolute";
      c.style.left = "0";
      c.style.top = "0";
      c.style.pointerEvents = "none";
      c.style.zIndex = "45";
      c.setAttribute("aria-hidden", "true");
      const host = map.getCanvasContainer && map.getCanvasContainer();
      if (host) host.appendChild(c);
      else map.getContainer().appendChild(c);
      wf.canvas = c;
      const dc = document.createElement("canvas");
      dc.style.position = "absolute";
      dc.style.left = "0";
      dc.style.top = "0";
      dc.style.pointerEvents = "none";
      dc.style.zIndex = "46";
      dc.setAttribute("aria-hidden", "true");
      if (host) host.appendChild(dc);
      else map.getContainer().appendChild(dc);
      wf.dbgCanvas = dc;

      wf.onMoveStart = function () {
        wfSyncFlowCanvasSize(map, wf.canvas);
        wfSyncFlowCanvasSize(map, wf.dbgCanvas);
        try {
          const ctx = wf.canvas.getContext("2d");
          if (ctx) ctx.clearRect(0, 0, wf.canvas.width, wf.canvas.height);
        } catch (_) {}
      };
      wf.onResize = function () {
        wfSyncFlowCanvasSize(map, wf.canvas);
        wfSyncFlowCanvasSize(map, wf.dbgCanvas);
      };
      map.on("movestart", wf.onMoveStart);
      map.on("resize", wf.onResize);
      fmpDbg("[wfEnsureWindyFlow] flow canvas DOM attached");
    }

    if (wf.raf == null) {
      wf.lastTs = typeof performance !== "undefined" ? performance.now() : 0;
      wf.simAccum = 0;
      const tick = function (now) {
        if (!maps[item.containerId] || maps[item.containerId] !== item) {
          wfDestroyFlowRenderer(item);
          return;
        }
        if (!item.showFlowLayer) {
          wfDestroyFlowRenderer(item);
          return;
        }
        const wf2 = item._windyFlow;
        if (!wf2) return;

        const ctx = wf2.canvas.getContext("2d", { alpha: true });
        const ctxDbg = wf2.dbgCanvas.getContext("2d", { alpha: true });
        wfSyncFlowCanvasSize(map, wf2.canvas);
        wfSyncFlowCanvasSize(map, wf2.dbgCanvas);

        const tau = wfClampTau(item.flowDataTau);
        let dtWall = 0;
        if (wf2.lastTs > 0) {
          dtWall = Math.min(0.12, Math.max(0, (now - wf2.lastTs) / 1000));
        }
        wf2.lastTs = now;

        // T_sim catch-up（與 RAF 解耦；render 只吃最新粒子狀態）
        wf2.simAccum += dtWall;
        const maxLag = WF_DT_SIM * 6;
        if (wf2.simAccum > maxLag) wf2.simAccum = maxLag;
        while (wf2.simAccum >= WF_DT_SIM) {
          wf2.simAccum -= WF_DT_SIM;
          wfAdvancePhysics(wf2, item, WF_DT_SIM, tau);
        }

        const noFade = (wf2.debugMask & WF_DBG_NO_FADE) !== 0;
        if (!noFade) {
          ctx.globalCompositeOperation = "destination-in";
          ctx.fillStyle = "rgba(" + 0 + "," + 0 + "," + 0 + "," + WF_FADE_ALPHA + ")";
          ctx.fillRect(0, 0, wf2.canvas.width, wf2.canvas.height);
          ctx.globalCompositeOperation = "source-over";
        } else {
          ctx.clearRect(0, 0, wf2.canvas.width, wf2.canvas.height);
        }

        ctx.lineWidth = WF_LINE_WIDTH;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";

        let b;
        try {
          b = map.getBounds();
        } catch (_) {
          b = null;
        }
        const pad = 0.18;
        const west = b ? b.getWest() - pad : -180;
        const east = b ? b.getEast() + pad : 180;
        const south = b ? b.getSouth() - pad : -90;
        const north = b ? b.getNorth() + pad : 90;

        const tracerOnly = (wf2.debugMask & WF_DBG_TRACER) !== 0;
        const dbgNearest = (wf2.debugMask & WF_DBG_NEAREST) !== 0;

        for (let i = 0; i < WF_PARTICLE_N; i++) {
          if (tracerOnly && i !== 0) continue;
          const lng0 = wf2.prev_lngs[i];
          const lat0 = wf2.prev_lats[i];
          const lng1 = wf2.lngs[i];
          const lat1 = wf2.lats[i];
          if (lng1 < west || lng1 > east || lat1 < south || lat1 > north) continue;
          if (Math.abs(lng1 - lng0) > 180) continue;

          let sMid = wfSampleUV(
            wf2.grid,
            (lng0 + lng1) * 0.5,
            (lat0 + lat1) * 0.5,
            tau,
            dbgNearest,
          );
          let spd = sMid.ok ? Math.hypot(sMid.u, sMid.v) : 0;
          const li = wfSpeedToLutIdx(spd);
          const o = li * 4;
          ctx.strokeStyle =
            "rgba(" +
            WF_LUT_RGBA[o] +
            "," +
            WF_LUT_RGBA[o + 1] +
            "," +
            WF_LUT_RGBA[o + 2] +
            "," +
            (WF_LUT_RGBA[o + 3] / 255).toFixed(3) +
            ")";

          try {
            const p0 = map.project([lng0, lat0]);
            const p1 = map.project([lng1, lat1]);
            const dx = p1.x - p0.x;
            const dy = p1.y - p0.y;
            if (dx * dx + dy * dy > 360000) continue;
            ctx.beginPath();
            ctx.moveTo(p0.x, p0.y);
            ctx.lineTo(p1.x, p1.y);
            ctx.stroke();
          } catch (_) {}
        }

        ctxDbg.clearRect(0, 0, wf2.dbgCanvas.width, wf2.dbgCanvas.height);
        if ((wf2.debugMask & (WF_DBG_ARROWS | WF_DBG_GRID)) !== 0) {
          wfDrawDebugOverlays(wf2, item, map, ctxDbg);
        }

        wf2.raf = requestAnimationFrame(tick);
      };
      wf.raf = requestAnimationFrame(tick);
    }
  }

  /** D1–D4 + nearest（僅 debug）： bitmask 見 WF_DBG_* */
  window.flowRendererSetDebug = function (containerId, mask) {
    const item = maps[containerId];
    if (!item || !item._windyFlow) return;
    item._windyFlow.debugMask = Number(mask) | 0;
  };

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
    showFlowLayer,
    flowGeoJsonT0,
    flowGeoJsonT1,
    flowDataTauStr,
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
            showFlowLayer,
            flowGeoJsonT0,
            flowGeoJsonT1,
            flowDataTauStr,
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

    let mergedShowFlow = parseShowCwaFlag(showFlowLayer);
    let mergedFlow0 = flowGeoJsonT0 || '{"type":"FeatureCollection","features":[]}';
    let mergedFlow1 =
      flowGeoJsonT1 && String(flowGeoJsonT1).trim() !== ""
        ? flowGeoJsonT1
        : mergedFlow0;
    let mergedTau = wfClampTau(parseFloat(String(flowDataTauStr || "0")));
    if (Number.isNaN(mergedTau)) mergedTau = 0;
    if (pendingFlowStore[containerId]) {
      const pf = pendingFlowStore[containerId];
      mergedShowFlow = parseShowCwaFlag(pf.show);
      mergedFlow0 = pf.t0 || mergedFlow0;
      mergedFlow1 = pf.t1 && String(pf.t1).trim() !== "" ? pf.t1 : mergedFlow0;
      mergedTau = wfClampTau(parseFloat(String(pf.tau != null ? pf.tau : "0")));
      if (Number.isNaN(mergedTau)) mergedTau = 0;
      delete pendingFlowStore[containerId];
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
      containerId,
      onMapClick,
      onSpotClick,
      styleId,
      spotData: mergedSpots,
      cwaData: mergedCwa,
      showCwaTide: mergedShowTide,
      showCwaBuoy: mergedShowBuoy,
      // wfEnsureWindyFlow 讀 item.showFlowLayer／flowGeoJson／τ；未寫入時 load 內為 undefined，等同永遠關閉粒子。
      showFlowLayer: mergedShowFlow,
      flowGeoJsonT0: mergedFlow0,
      flowGeoJsonT1: mergedFlow1,
      flowDataTau: mergedTau,
    };
    maps[containerId] = item;

    map.on("load", () => {
      fmpDbg("[map load] id=" + String(containerId));
      applyLanguage(map, languageField);
      ensureCwaStationLayers(map, item);
      if (!map.getSource("spots")) {
        map.addSource(
          "spots",
          spotsSourceSpec(toFeatureCollection(item.spotData))
        );
      }
      ensureSpotClusterLayers(map);
      wireMapClickHandlers(item);
      patchMapboxFlutterPlatformViewA11y(map);
      try {
        wfEnsureWindyFlow(item, map);
      } catch (_) {}
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
    showFlowLayer,
    flowGeoJsonT0,
    flowGeoJsonT1,
    flowDataTauStr,
    onMapClick,
    onSpotClick
  ) {
    const spots = JSON.parse(spotsJson || "[]");
    const cwaStations = JSON.parse(cwaStationsJson || "[]");
    const showTide = parseShowCwaFlag(showCwaTideLayer);
    const showBuoy = parseShowCwaFlag(showCwaBuoyLayer);
    const showFlow = parseShowCwaFlag(showFlowLayer);
    try {
      var pj0 = JSON.parse(flowGeoJsonT0 || "{}");
      fmpDbg(
        "[fishingMapCreate] id=" +
          String(containerId) +
          " showFlow=" +
          String(showFlow) +
          " f0.features.len=" +
          String(
            pj0.features && pj0.features.length ? pj0.features.length : 0
          )
      );
    } catch (_) {
      fmpDbg("[fishingMapCreate] id=" + String(containerId) + " f0 parse fail");
    }
    createWhenReady(
      containerId,
      accessToken,
      styleId,
      languageField,
      spots,
      cwaStations,
      showTide,
      showBuoy,
      showFlow,
      flowGeoJsonT0 || '{"type":"FeatureCollection","features":[]}',
      flowGeoJsonT1 || "",
      flowDataTauStr || "0",
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
    showFlowLayer,
    flowGeoJsonT0,
    flowGeoJsonT1,
    flowDataTauStr
  ) {
    const spots = JSON.parse(spotsJson || "[]");
    const cwaStations = JSON.parse(cwaStationsJson || "[]");
    const showTide = parseShowCwaFlag(showCwaTideLayer);
    const showBuoy = parseShowCwaFlag(showCwaBuoyLayer);
    const showFlow = parseShowCwaFlag(showFlowLayer);
    const f0 = flowGeoJsonT0 || '{"type":"FeatureCollection","features":[]}';
    const f1 =
      flowGeoJsonT1 && String(flowGeoJsonT1).trim() !== "" ? flowGeoJsonT1 : f0;
    let tauU = wfClampTau(parseFloat(String(flowDataTauStr || "0")));
    if (Number.isNaN(tauU)) tauU = 0;

    let item = maps[containerId];
    let f0FeatN = 0;
    try {
      var _pj = JSON.parse(f0 || "{}");
      f0FeatN =
        _pj.features && _pj.features.length ? _pj.features.length : 0;
    } catch (_) {}
    if (!item) {
      fmpDbg(
        "[fishingMapUpdate] PENDING no item id=" +
          String(containerId) +
          " showFlow=" +
          String(showFlow) +
          " f0.features.len=" +
          String(f0FeatN)
      );
      pendingSpotUpdates[containerId] = spots;
      pendingCwaStore[containerId] = {
        stations: cwaStations,
        showTide: showTide,
        showBuoy: showBuoy,
      };
      pendingFlowStore[containerId] = {
        show: showFlow,
        t0: f0,
        t1: f1,
        tau: tauU,
      };
      return;
    }
    const map = item.map;
    const nextStyle = getStyleUrl(styleId);
    const styleChanging = item.styleId !== styleId;
    fmpDbg(
      "[fishingMapUpdate] id=" +
        String(containerId) +
        " showFlow=" +
        String(showFlow) +
        " f0.features.len=" +
        String(f0FeatN) +
        " styleChanging=" +
        String(styleChanging)
    );

    item.spotData = spots;
    item.cwaData = cwaStations;
    item.showCwaTide = showTide;
    item.showCwaBuoy = showBuoy;
    item.showFlowLayer = showFlow;
    item.flowGeoJsonT0 = f0;
    item.flowGeoJsonT1 = f1;
    item.flowDataTau = tauU;

    function applySameStyleDelta() {
      if (!maps[containerId] || maps[containerId] !== item) return;

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
      patchMapboxFlutterPlatformViewA11y(map);
      // 同風格 delta 也必須同步海流（否則僅 map load／換風格 idle 會跑，勾選開關永遠不會建 canvas／RAF）。
      fmpDbg("[applySameStyleDelta] call wfEnsureWindyFlow");
      try {
        wfEnsureWindyFlow(item, map);
      } catch (_) {}
    }

    if (styleChanging) {
      item.styleId = styleId;
      runAfterMapStyleReady(map, function applyStyleSwap() {
        if (!maps[containerId] || maps[containerId] !== item) return;
        map.setStyle(nextStyle);
        // styledata 常過早；idle 確保可依賴 sources/layers API，並可重綁 click。
        map.once("idle", () => {
          if (!maps[containerId] || maps[containerId] !== item) return;
          applyLanguage(map, languageField);
          ensureCwaStationLayers(map, item);
          const splitIdle = toCwaSplitCollections(item.cwaData);
          const tideNow = map.getSource("cwa-tide-stations");
          if (tideNow && typeof tideNow.setData === "function") {
            tideNow.setData(splitIdle.tide);
          }
          const buoyNow = map.getSource("cwa-buoy-stations");
          if (buoyNow && typeof buoyNow.setData === "function") {
            buoyNow.setData(splitIdle.buoy);
          }
          setCwaClusterLayerVisibility(
            map,
            item.showCwaTide ? "visible" : "none",
            item.showCwaBuoy ? "visible" : "none"
          );
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
          patchMapboxFlutterPlatformViewA11y(map);
          fmpDbg("[style idle] wfEnsureWindyFlow");
          try {
            wfEnsureWindyFlow(item, map);
          } catch (_) {}
        });
      });
      return;
    }

    runAfterMapStyleReady(map, applySameStyleDelta);
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
    let on = false;
    if (typeof enabled === "number") {
      on = enabled !== 0;
    } else if (typeof enabled === "boolean") {
      on = enabled;
    } else {
      on = !!enabled;
    }
    for (const id of Object.keys(maps)) {
      const m = maps[id] && maps[id].map;
      if (!m) continue;
      try {
        setMapInteractions(m, on);
        const el = typeof m.getContainer === "function" ? m.getContainer() : null;
        if (el && el.style) {
          el.style.pointerEvents = on ? "" : "none";
        }
      } catch (_) {}
    }
  };

  window.fishingMapDispose = function (containerId) {
    fmpDbg("[fishingMapDispose] id=" + String(containerId));
    const item = maps[containerId];
    if (!item) return;
    try {
      wfDestroyFlowRenderer(item);
    } catch (_) {}
    item.map.remove();
    delete maps[containerId];
    delete pendingSpotUpdates[containerId];
    delete pendingCwaStore[containerId];
    delete pendingFlowStore[containerId];
  };
})();
