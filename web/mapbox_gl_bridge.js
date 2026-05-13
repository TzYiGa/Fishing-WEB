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

  /** Web Mapbox：固定釣點（地標感圖釘）。 */
  const SPOT_FISHING_POI_MARKER_SVG =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">' +
    '<path fill="#c2410c" stroke="#fffefc" stroke-width="1.35" stroke-linejoin="round" d="M16 2.6c-4.4 0-8 3.4-8 7.6 0 5.45 8 18.8 8 18.8s8-13.35 8-18.8c0-4.2-3.6-7.6-8-7.6z"/>' +
    '<circle cx="16" cy="10.3" r="3.25" fill="#fff7ed"/>' +
    "</svg>";

  /** Web Mapbox：釣況分享（相機快照感圖示，與固定釣點區隔）。 */
  const SPOT_CONDITION_SHARE_MARKER_SVG =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">' +
    '<circle cx="16" cy="16" r="13" fill="#0369a1" stroke="#e0f2fe" stroke-width="1.45"/>' +
    '<rect x="7.2" y="10.2" width="17.6" height="12" rx="2.8" fill="#f0f9ff" stroke="#bae6fd" stroke-width="0.7"/>' +
    '<path fill="#0369a1" d="M12.8 10.1l1.2-2.1h4l1.2 2.1z"/>' +
    '<circle cx="16" cy="16.2" r="3.3" fill="#0369a1"/>' +
    '<circle cx="16" cy="16.2" r="1.7" fill="#bae6fd"/>' +
    '<circle cx="21.8" cy="13.3" r="0.9" fill="#0c4a6e"/>' +
    "</svg>";

  /** 潮位觀測站「叢集」專用：圓角方塊＋波浪＋小「＋」表示多站合併（與單站圓形圖示區隔）。 */
  const CWA_TIDE_CLUSTER_BADGE_SVG =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">' +
    '<rect x="2.5" y="2.5" width="27" height="27" rx="8" fill="#f0f9ff" stroke="#0284c7" stroke-width="2"/>' +
    '<path fill="none" stroke="#0369a1" stroke-width="2" stroke-linecap="round" d="M6 19q4-4 8 0t8 0 8-3"/>' +
    '<path fill="none" stroke="#0c4a6e" stroke-width="1.5" stroke-linecap="round" d="M6 23.5q4-3.5 8 0t9-1"/>' +
    '<circle cx="23.5" cy="9.5" r="5" fill="#38bdf8" stroke="#fff" stroke-width="1.3"/>' +
    '<path stroke="#fff" stroke-width="1.4" stroke-linecap="round" d="M21.2 9.5h4.6M23.5 7.2v4.6"/>' +
    "</svg>";

  /** 浮標站「叢集」專用：圓角方塊＋簡化浮標＋小「＋」表示多站合併。 */
  const CWA_BUOY_CLUSTER_BADGE_SVG =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">' +
    '<rect x="2.5" y="2.5" width="27" height="27" rx="8" fill="#fffbeb" stroke="#ea580c" stroke-width="2"/>' +
    '<ellipse cx="16" cy="19" rx="8" ry="4.5" fill="#fb923c" stroke="#c2410c" stroke-width="1"/>' +
    '<rect x="15" y="8.5" width="2" height="8" rx="1" fill="#78350f"/>' +
    '<circle cx="16" cy="7" r="1.6" fill="#fdba74" stroke="#9a3412" stroke-width="0.4"/>' +
    '<circle cx="23.5" cy="9.5" r="5" fill="#f97316" stroke="#fff" stroke-width="1.3"/>' +
    '<path stroke="#fff" stroke-width="1.4" stroke-linecap="round" d="M21.2 9.5h4.6M23.5 7.2v4.6"/>' +
    "</svg>";

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
      if (layer.id === "spots-cluster-icons") continue;
      if (
        layer.id === "cwa-tide-label" ||
        layer.id === "cwa-buoy-label" ||
        layer.id === "cwa-tide-icon" ||
        layer.id === "cwa-buoy-icon" ||
        layer.id === "cwa-tide-unclustered" ||
        layer.id === "cwa-buoy-unclustered" ||
        layer.id === "cwa-tide-cluster-icons" ||
        layer.id === "cwa-buoy-cluster-icons"
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
      features: (spots || []).map((s) => {
        const catFromList =
          Array.isArray(s.categoryIds) && s.categoryIds.length
            ? String(s.categoryIds[0])
            : "";
        const catPrimary = String(
          s.category != null && s.category !== ""
            ? s.category
            : catFromList || "1-2",
        );
        const ekRaw =
          s.entryKind != null && String(s.entryKind) !== ""
            ? String(s.entryKind)
            : "conditionShare";
        const entryKindNorm = ekRaw === "fishingPoi" ? "fishingPoi" : "conditionShare";
        return {
          type: "Feature",
          geometry: {
            type: "Point",
            coordinates: [s.lng, s.lat],
          },
          properties: {
            id: String(s.id),
            category: catPrimary,
            entryKind: entryKindNorm,
          },
        };
      }),
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
      "cwa-buoy-cluster-icons",
      "cwa-buoy-clusters",
      "cwa-tide-label",
      "cwa-tide-unclustered",
      "cwa-tide-cluster-icons",
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
      "cwa-tide-cluster-icons",
      "cwa-tide-unclustered",
      "cwa-tide-label",
    ];
    const buoy = [
      "cwa-buoy-clusters",
      "cwa-buoy-cluster-icons",
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
    if (!map.getLayer("cwa-tide-cluster-icons")) {
      map.addLayer({
        id: "cwa-tide-cluster-icons",
        type: "symbol",
        source: "cwa-tide-stations",
        filter: ["has", "point_count"],
        layout: {
          "icon-image": "cwa-tide-cluster-mark",
          "icon-size": 0.56,
          "icon-allow-overlap": true,
          "icon-ignore-placement": true,
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
          "icon-ignore-placement": true,
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
    if (!map.getLayer("cwa-buoy-cluster-icons")) {
      map.addLayer({
        id: "cwa-buoy-cluster-icons",
        type: "symbol",
        source: "cwa-buoy-stations",
        filter: ["has", "point_count"],
        layout: {
          "icon-image": "cwa-buoy-cluster-mark",
          "icon-size": 0.56,
          "icon-allow-overlap": true,
          "icon-ignore-placement": true,
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
          "icon-ignore-placement": true,
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
    if (
      map.hasImage("cwa-tide-marker") &&
      map.hasImage("cwa-buoy-marker") &&
      map.hasImage("cwa-tide-cluster-mark") &&
      map.hasImage("cwa-buoy-cluster-mark")
    ) {
      done();
      return;
    }
    var pending = 0;
    function oneDone() {
      pending--;
      if (pending <= 0) done();
    }
    function addInlineClusterMark(id, svgText) {
      if (map.hasImage(id)) return;
      pending++;
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
    function loadSvgAsset(id, relUrl, fallbackSvg) {
      if (map.hasImage(id)) {
        return;
      }
      pending++;
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
    addInlineClusterMark("cwa-tide-cluster-mark", CWA_TIDE_CLUSTER_BADGE_SVG);
    addInlineClusterMark("cwa-buoy-cluster-mark", CWA_BUOY_CLUSTER_BADGE_SVG);
    if (pending <= 0) done();
  }

  /** 釣點單點／叢集 symbol：依 entryKind 與叢集統計切換圖示（換 style 後須可重加）。 */
  function ensureSpotMarkerImagesLoaded(map, done) {
    if (
      map.hasImage("spot-icon-fishing-poi") &&
      map.hasImage("spot-icon-condition-share")
    ) {
      done();
      return;
    }
    var pending = 0;
    function oneDone() {
      pending--;
      if (pending <= 0) done();
    }
    function addFromSvg(id, svgText) {
      if (map.hasImage(id)) return;
      pending++;
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
    addFromSvg("spot-icon-fishing-poi", SPOT_FISHING_POI_MARKER_SVG);
    addFromSvg("spot-icon-condition-share", SPOT_CONDITION_SHARE_MARKER_SVG);
    if (pending <= 0) done();
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
        addCwaTideClusterLayers(map);
        addCwaBuoyClusterLayers(map);
      }
      setCwaClusterLayerVisibility(map, visTide, visBuoy);
      reorderSpotAndCwaLayers(map);
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
  /** RAF 牆鐘時間 → 模擬秒縮放；與 wfFlowMotionScale 併用 */
  const WF_ANIM_FACTOR_DEFAULT = 168;
  /** 沿流場平流（u,v）總倍率（與調參 advectionSpeedMul 預設一致） */
  const WF_ADVECTION_SPEED_MUL_DEFAULT = 24;
  /** true 時每一 slice 印 [wf.advance]（量大）；通常只開 [wf.tick] */
  const WF_ADV_VERBOSE_FLAG = "FISHING_FLOW_VERBOSE_DEBUG";
  /** 視覺密度（非線寬）；勿設過大以免低階裝置掉幀 */
  /** 參考 Windy：密度中等即可，過密易成糊塊 */
  const WF_PARTICLE_N = 500;
  /** false：不顯示右下角「粒子調參」按鈕；仍可依 globalThis.fishingFlowParticleTuning 或由程式調參。 */
  const WF_PARTICLE_TUNING_PANEL_UI = false;
  /** 拖尾最短邊／粒子可見度（CSS px→buffer） */
  /** 與 wfEnsureMinStreakExtent 並用；過小易在 DPR 高時仍像光點 */
  const WF_MIN_STROKE_CSS_PX = 5.5;
  /** 每幀「上一幀快照 → 當前頭」在螢幕上至少移動幾個 CSS 像素（換算成 map buffer），避免 0.0x 像素像沒動 */
  const WF_MIN_FRAME_STRIDE_CSS_PX = 1;
  /** 可選：globalThis.FISHING_FLOW_MIN_STROKE_CSS_PX */
  const WF_REF_ZOOM = 7.5;
  /** Canvas 淡出（數值愈小全域殘影愈短）；略高仍保持單粒子「細條」可辨 */
  const WF_FADE_ALPHA = 0.82;
  /** 視覺上接近 Windy 的細線條痕（過粗会像螢光棒而非流線） */
  const WF_LINE_WIDTH = 1.58;
  /** Windy 風格偏銳利，blur 過重会像光暈粒子 */
  const WF_METEOR_SHADOW_BLUR = 3.5;
  /** 小圓點頭＋細線較接近參考圖的 streak */
  const WF_HEAD_CAP_MUL = 0.48;
  const WF_LINE_DRAW_MIN_BUF = 1.2;
  const WF_LINE_DRAW_MAX_BUF = 3.8;
  /**
   * 「貪吃蛇」鏈結：索引 0 為頭，每一節為上一時間步頭位；鏈結加長可避免只像「頭對尾一條細線」。
   * 繪製時 WF_SNAKE_MAX_PATH_DEG 軟裁剪，且至少保留 WF_SNAKE_MIN_DRAW_VERTS 個轉折前有中段身體。
   */
  /** 略少於極長蛇身，畫面較像參考圖的短 streak */
  const WF_SNAKE_SEG = 12;
  /** 單條痕在地理上不要太長，避免像粗蟲；仍須夠長以顯示流向 */
  const WF_SNAKE_MAX_PATH_DEG = 3.15;
  const WF_SNAKE_ABSOLUTE_MAX_PATH_DEG = 6.5;
  const WF_SNAKE_MIN_DRAW_VERTS = 4;
  /** 每子步推入鏈結 → 折線較密、更像連續流線（Windy 感） */
  const WF_SNAKE_PUSH_EVERY_N_SUB = 1;
  const WF_SPEED_EPS = 0.025;
  /**
   * 粒子累積沿流場移動此距離（公尺）後重生；另加隨機額度使畫面不齊步。
   * 概念：在當地取流向 → 平流前進 → 走夠遠就刪除再隨機生一顆。
   */
  const WF_TRAVEL_BUDGET_MIN_M = 22000;
  const WF_TRAVEL_BUDGET_EXTRA_M = 48000;
  const WF_DBG_ARROWS = 1;
  const WF_DBG_TRACER = 2;
  const WF_DBG_GRID = 4;
  const WF_DBG_NO_FADE = 8;
  const WF_DBG_NEAREST = 16;

  function wfParticleTuningBuiltinDefaults() {
    return {
      animFactor: WF_ANIM_FACTOR_DEFAULT,
      particleCount: WF_PARTICLE_N,
      minStrokeCssPx: WF_MIN_STROKE_CSS_PX,
      minFrameStrideCssPx: WF_MIN_FRAME_STRIDE_CSS_PX,
      advectionSpeedMul: WF_ADVECTION_SPEED_MUL_DEFAULT,
      fadeAlpha: WF_FADE_ALPHA,
      lineWidth: WF_LINE_WIDTH,
      meteorShadowBlur: WF_METEOR_SHADOW_BLUR,
      headCapMul: WF_HEAD_CAP_MUL,
      lineDrawMinBuf: WF_LINE_DRAW_MIN_BUF,
      lineDrawMaxBuf: WF_LINE_DRAW_MAX_BUF,
      snakeSeg: WF_SNAKE_SEG,
      snakeMaxPathDeg: WF_SNAKE_MAX_PATH_DEG,
      snakeAbsMaxPathDeg: WF_SNAKE_ABSOLUTE_MAX_PATH_DEG,
      snakeMinDrawVerts: WF_SNAKE_MIN_DRAW_VERTS,
      snakePushEveryNSub: WF_SNAKE_PUSH_EVERY_N_SUB,
      travelBudgetMinM: WF_TRAVEL_BUDGET_MIN_M,
      travelBudgetExtraM: WF_TRAVEL_BUDGET_EXTRA_M,
      simWallMinFrac: 0.06,
      simWallMaxMul: 56,
      dtSim: WF_DT_SIM,
      speedEps: WF_SPEED_EPS,
    };
  }

  function wfBootstrapFlowParticleTuning() {
    if (typeof globalThis === "undefined") return;
    const d = wfParticleTuningBuiltinDefaults();
    if (
      !globalThis.fishingFlowParticleTuning ||
      typeof globalThis.fishingFlowParticleTuning !== "object"
    ) {
      globalThis.fishingFlowParticleTuning = {};
    }
    const t = globalThis.fishingFlowParticleTuning;
    for (const k in d) {
      if (
        t[k] === undefined ||
        t[k] === null ||
        (typeof t[k] === "number" && Number.isNaN(t[k]))
      )
        t[k] = d[k];
    }
  }

  function wfParticleTuningSnapshot() {
    wfBootstrapFlowParticleTuning();
    const d = wfParticleTuningBuiltinDefaults();
    const t = globalThis.fishingFlowParticleTuning || {};
    function num(k, lo, hi) {
      let v = Number(t[k]);
      if (Number.isNaN(v)) v = d[k];
      if (typeof lo === "number" && v < lo) v = lo;
      if (typeof hi === "number" && v > hi) v = hi;
      return v;
    }
    function intr(k, lo, hi) {
      return Math.round(num(k, lo, hi));
    }
    return {
      animFactor: num("animFactor", 8, 720),
      particleCount: intr("particleCount", 50, 10000),
      minStrokeCssPx: num("minStrokeCssPx", 0.5, 36),
      minFrameStrideCssPx: num("minFrameStrideCssPx", 1, 12),
      advectionSpeedMul: num("advectionSpeedMul", 0.15, 24),
      fadeAlpha: num("fadeAlpha", 0.35, 0.999),
      lineWidth: num("lineWidth", 0.4, 34),
      meteorShadowBlur: num("meteorShadowBlur", 0, 52),
      headCapMul: num("headCapMul", 0, 5),
      lineDrawMinBuf: num("lineDrawMinBuf", 0.3, 34),
      lineDrawMaxBuf: num("lineDrawMaxBuf", 1, 72),
      snakeSeg: intr("snakeSeg", 2, 64),
      snakeMaxPathDeg: num("snakeMaxPathDeg", 0.02, 8),
      snakeAbsMaxPathDeg: num("snakeAbsMaxPathDeg", 0.05, 12),
      snakeMinDrawVerts: intr("snakeMinDrawVerts", 2, 24),
      snakePushEveryNSub: intr("snakePushEveryNSub", 1, 20),
      travelBudgetMinM: num("travelBudgetMinM", 800, 2e6),
      travelBudgetExtraM: num("travelBudgetExtraM", 0, 2e6),
      simWallMinFrac: num("simWallMinFrac", 0.01, 3),
      simWallMaxMul: intr("simWallMaxMul", 1, 400),
      dtSim: num("dtSim", 0.15, 16),
      speedEps: num("speedEps", 1e-5, 8),
    };
  }

  /**
   * 面板上的 particleCount 視為「參考縮放 WF_REF_ZOOM 時的底數」：放大（高 zoom）可視海域變小，
   * 提高有效粒子數以維持畫面密度；縮小地圖則減量省 CPU。以 0.5 級 zoom 量化，減少陣列反覆重配。
   */
  function wfEffectiveParticleCountForZoom(baseParticleCount, zoom) {
    let b = baseParticleCount | 0;
    if (b < 50) b = 50;
    if (b > 10000) b = 10000;
    const z = Number(zoom);
    if (!Number.isFinite(z)) return b;
    const zq = Math.round(z * 2) / 2;
    let exp = (zq - WF_REF_ZOOM) * 0.82;
    if (exp > 14) exp = 14;
    if (exp < -3.5) exp = -3.5;
    const mul = Math.pow(2, exp);
    let n = Math.round(b * mul);
    if (n < 50) n = 50;
    if (n > 10000) n = 10000;
    return n | 0;
  }

  function wfFlowAdvVerbose() {
    return (
      typeof globalThis !== "undefined" &&
      globalThis[WF_ADV_VERBOSE_FLAG] === true
    );
  }

  /** 預設關閉；每幀 fmpDbg→Dart 很傷效能且易觸發 Chrome [Violation]。除錯時：globalThis.FISHING_FLOW_TICK_DEBUG=true */
  const WF_TICK_DEBUG_FLAG = "FISHING_FLOW_TICK_DEBUG";
  function wfFlowTickDbg() {
    return (
      typeof globalThis !== "undefined" &&
      globalThis[WF_TICK_DEBUG_FLAG] === true
    );
  }

  /**
   * minStrokeCssPx：可傳 wfParticleTuningSnapshot().minStrokeCssPx，避免重複取 snapshot。
   * 仍支援 globalThis.FISHING_FLOW_MIN_STROKE_CSS_PX 覆寫（與舊主控台相容）。
   */
  function wfMinStrokeBufPxFor(map, minStrokeCssPx) {
    let css =
      typeof minStrokeCssPx === "number" && !Number.isNaN(minStrokeCssPx)
        ? minStrokeCssPx
        : wfParticleTuningSnapshot().minStrokeCssPx;
    if (typeof globalThis !== "undefined") {
      const ov = globalThis.FISHING_FLOW_MIN_STROKE_CSS_PX;
      if (ov != null && !Number.isNaN(Number(ov))) {
        css = Math.max(1, Math.min(36, Number(ov)));
      }
    }
    try {
      const mc = map && map.getCanvas && map.getCanvas();
      if (
        mc &&
        mc.clientWidth &&
        mc.clientWidth > 0 &&
        mc.width &&
        mc.width > 0
      ) {
        return css * (mc.width / mc.clientWidth);
      }
    } catch (_) {}
    const dpr =
      typeof window !== "undefined" && window.devicePixelRatio
        ? window.devicePixelRatio
        : 1;
    return css * Math.max(1, dpr);
  }

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

  /** 兩點間近似平面距離（公尺），供粒子「走滿一段路就重生」 */
  function wfDeltaMetersLngLat(lng0, lat0, lng1, lat1) {
    const mp = wfMetersPerDeg(0.5 * (lat0 + lat1));
    const dlat = lat1 - lat0;
    let dlng = lng1 - lng0;
    if (dlng > 180) dlng -= 360;
    if (dlng < -180) dlng += 360;
    return Math.hypot(dlat * mp.mLat, dlng * mp.mLng);
  }

  function wfWrapLongitude(lng) {
    let x = lng;
    while (x > 180) x -= 360;
    while (x < -180) x += 360;
    return x;
  }

  /** 兩經緯點之間線性中點（經度走最短弧）；用於蛇身 1/2 重疊節點。 */
  function wfMidLngLat(lng0, lat0, lng1, lat1) {
    let dlng = lng1 - lng0;
    if (dlng > 180) dlng -= 360;
    if (dlng < -180) dlng += 360;
    return {
      lng: wfWrapLongitude(lng0 + 0.5 * dlng),
      lat: lat0 + 0.5 * (lat1 - lat0),
    };
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
    if (!Number.isNaN(u) && !Number.isNaN(v)) return { ok: true, u, v };
    /** 鄰角若有缺資料(NaN)，雙線性會報 NaN→易觸發重生，看起來像「任意方向冒出」。改用最近一格有效向量保沿場方向。 */
    let ix = Math.round(fx);
    let iy = Math.round(fy);
    if (ix < 0) ix = 0;
    if (iy < 0) iy = 0;
    if (ix >= nx) ix = nx - 1;
    if (iy >= ny) iy = ny - 1;
    const un = Uat(ix, iy);
    const vn = Vat(ix, iy);
    if (!Number.isNaN(un) && !Number.isNaN(vn)) return { ok: true, u: un, v: vn };
    return { ok: false, u: 0, v: 0 };
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

  /** 舊式：高 zoom → 极小值（粒子像凍結）。僅保留供非流場程式若仍引用。 */
  function wfZoomCompensation(map) {
    try {
      const z = map.getZoom();
      return Math.pow(2, WF_REF_ZOOM - z);
    } catch (_) {
      return 1;
    }
  }

  /**
   * 視覺可動流速倍率（不依賴 snapshot，供每幀／每 slice 熱路徑呼叫）。
   * advectionMul 取自當幀已快照的調參，避免 wfParticleTuningSnapshot() 在每個 slice 重跑。
   */
  function wfFlowMotionScaleCore(map, advectionMul) {
    let z = WF_REF_ZOOM;
    try {
      z = map.getZoom();
    } catch (_) {}
    const raw = Math.pow(2, (z - WF_REF_ZOOM) * 0.95);
    const base = Math.max(1, Math.min(raw, 720));
    const mul =
      typeof advectionMul === "number" && !Number.isNaN(advectionMul)
        ? advectionMul
        : WF_ADVECTION_SPEED_MUL_DEFAULT;
    return base * Math.max(0.05, mul);
  }

  /** 相機正在動（平移縮放等）：用於 debug overlay，避免長幀；粒子模擬不因本旗標暫停。 */
  function wfMapIsInteracting(map, wf2) {
    if (wf2 && wf2.mapInteracting) return true;
    try {
      if (map && typeof map.isMoving === "function" && map.isMoving())
        return true;
    } catch (_) {}
    return false;
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
    const n =
      typeof w.nParticles === "number" && w.nParticles > 0
        ? w.nParticles | 0
        : WF_PARTICLE_N;
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
        const tun = item._flowParticleTuning || wfParticleTuningSnapshot();
        w.lngs[i] = lng;
        w.lats[i] = lat;
        w.prev_lngs[i] = lng;
        w.prev_lats[i] = lat;
        w.travelM[i] = 0;
        w.travelBudgetM[i] =
          tun.travelBudgetMinM + rng() * Math.max(0, tun.travelBudgetExtraM);
        wfSeedSnake(w, i);
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

  function wfSnakeDegDelta(lng0, lat0, lng1, lat1) {
    const dl = lng1 - lng0;
    if (!Number.isFinite(dl) || Math.abs(dl) > 170) return 999;
    const dlat = lat1 - lat0;
    return Math.hypot(dl, dlat);
  }

  /** 折線改為離頭較遠端在前，繪製由尾端到頭連成一條連續流星。 */
  function wfTailToHeadStrip(drawVerts, headPx) {
    const strip = drawVerts.slice();
    const ax = strip[0].x - headPx.x;
    const ay = strip[0].y - headPx.y;
    const bx = strip[strip.length - 1].x - headPx.x;
    const by = strip[strip.length - 1].y - headPx.y;
    if (ax * ax + ay * ay < bx * bx + by * by) strip.reverse();
    return strip;
  }

  /**
   * 單一路徑：尾端近透明→頭端較亮（對齊 Windy 類細條痕可讀性，與色相無關）。
   * lutOff 為 WF_LUT_RGBA 起始索引。
   */
  function wfStrokeMeteorTrail(
    ctx,
    strip,
    headPx,
    lutOff,
    linePxBuf,
    shadowBlurPx,
    headCapMul,
  ) {
    if (!strip || strip.length < 2) return;
    const r255 = WF_LUT_RGBA[lutOff];
    const g255 = WF_LUT_RGBA[lutOff + 1];
    const bl255 = WF_LUT_RGBA[lutOff + 2];
    const baseA = WF_LUT_RGBA[lutOff + 3] / 255;
    const x0 = strip[0].x;
    const y0 = strip[0].y;
    const x1 = strip[strip.length - 1].x;
    const y1 = strip[strip.length - 1].y;
    const grd = ctx.createLinearGradient(x0, y0, x1, y1);
    grd.addColorStop(
      0,
      "rgba(" +
        r255 +
        "," +
        g255 +
        "," +
        bl255 +
        "," +
        Math.max(0, Math.min(1, baseA * 0.05)).toFixed(3) +
        ")",
    );
    grd.addColorStop(
      0.35,
      "rgba(" +
        r255 +
        "," +
        g255 +
        "," +
        bl255 +
        "," +
        Math.max(0, Math.min(1, baseA * 0.32)).toFixed(3) +
        ")",
    );
    grd.addColorStop(
      0.78,
      "rgba(" +
        r255 +
        "," +
        g255 +
        "," +
        bl255 +
        "," +
        Math.max(0, Math.min(1, baseA * 0.72)).toFixed(3) +
        ")",
    );
    grd.addColorStop(
      1,
      "rgba(" +
        r255 +
        "," +
        g255 +
        "," +
        bl255 +
        "," +
        Math.max(0, Math.min(1, baseA * 0.98)).toFixed(3) +
        ")",
    );
    ctx.save();
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.miterLimit = 2;
    ctx.lineWidth = linePxBuf;
    ctx.strokeStyle = grd;
    ctx.shadowBlur =
      shadowBlurPx !== undefined && shadowBlurPx !== null
        ? shadowBlurPx
        : WF_METEOR_SHADOW_BLUR;
    ctx.shadowColor =
      "rgba(" +
        r255 +
        "," +
        g255 +
        "," +
        bl255 +
        "," +
        Math.min(1, baseA * 0.35).toFixed(3) +
        ")";
    ctx.beginPath();
    ctx.moveTo(strip[0].x, strip[0].y);
    for (let u = 1; u < strip.length; u++) {
      ctx.lineTo(strip[u].x, strip[u].y);
    }
    const lx = strip[strip.length - 1].x;
    const ly = strip[strip.length - 1].y;
    if (
      (lx - headPx.x) * (lx - headPx.x) + (ly - headPx.y) * (ly - headPx.y) >
      0.81
    ) {
      ctx.lineTo(headPx.x, headPx.y);
    }
    ctx.stroke();
    ctx.shadowBlur = 0;

    const mul =
      headCapMul !== undefined && headCapMul !== null ? headCapMul : WF_HEAD_CAP_MUL;
    const capR = Math.max(1.35, linePxBuf * mul);
    ctx.fillStyle =
      "rgba(" +
        r255 +
        "," +
        g255 +
        "," +
        bl255 +
        "," +
        Math.min(1, baseA * 0.95).toFixed(3) +
        ")";
    ctx.beginPath();
    ctx.arc(headPx.x, headPx.y, capR, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  /** 去掉投影後重疊的頂點，避免折線長度 0 只剩頭帽、看起來像原地閃點 */
  function wfDedupePxChain(verts, pxEps) {
    const eps2 = pxEps * pxEps;
    const out = [];
    for (let i = 0; i < verts.length; i++) {
      const p = verts[i];
      if (!out.length) {
        out.push(p);
        continue;
      }
      const q = out[out.length - 1];
      const dx = p.x - q.x;
      const dy = p.y - q.y;
      if (dx * dx + dy * dy >= eps2) out.push(p);
    }
    return out;
  }

  /**
   * strip：wfTailToHeadStrip 後 0=尾淡、末點朝頭；頭帽繪於 headPx。
   * 「尾頂點 ↔ 頭」若在 buffer 像素上太短→把尾順流方向往後拉到 minLenBuf（避免只剩圓帽像閃爍點）。
   */
  function wfEnsureMinStreakExtent(
    map,
    headPx,
    strip,
    minLenBuf,
    lngHead,
    latHead,
    grid,
    tau,
    dbgNearest,
  ) {
    if (!strip || strip.length < 2) return strip;
    const tail = strip[0];
    const fwdX = headPx.x - tail.x;
    const fwdY = headPx.y - tail.y;
    const streakLen = Math.hypot(fwdX, fwdY);
    if (streakLen >= minLenBuf) return strip;
    let ux;
    let uy;
    if (streakLen > 0.6) {
      ux = fwdX / streakLen;
      uy = fwdY / streakLen;
    } else {
      const s = wfSampleUV(grid, lngHead, latHead, tau, dbgNearest);
      if (!s.ok) {
        ux = 0;
        uy = -1;
      } else {
        const mp = wfMetersPerDeg(latHead);
        const dtG = 42;
        const lng1 = lngHead + (s.u / mp.mLng) * dtG;
        const lat1 = latHead + (s.v / mp.mLat) * dtG;
        try {
          const pFwd = wfMapProjectToCanvasBuffer(map, lng1, lat1);
          ux = pFwd.x - headPx.x;
          uy = pFwd.y - headPx.y;
          const un = Math.hypot(ux, uy);
          if (un < 0.8) {
            ux = 0;
            uy = -1;
          } else {
            ux /= un;
            uy /= un;
          }
        } catch (_) {
          ux = 0;
          uy = -1;
        }
      }
    }
    const tailX = headPx.x - ux * minLenBuf;
    const tailY = headPx.y - uy * minLenBuf;
    const next = strip.slice();
    next[0] = { x: tailX, y: tailY };
    return next;
  }

  /** 鏈結全疊為一點（重生／初始化） */
  function wfSeedSnake(w, i) {
    const sb =
      typeof w.snSeg === "number" && w.snSeg > 0 ? w.snSeg | 0 : WF_SNAKE_SEG;
    const b = i * sb;
    const lng = w.lngs[i];
    const lat = w.lats[i];
    for (let k = 0; k < sb; k++) {
      w.snLng[b + k] = lng;
      w.snLat[b + k] = lat;
    }
  }

  /**
   * 頭塞入當前座標；第二節為「上一頭 → 新頭」路徑的一半處（與頭重疊約 1/2 步長），非貼齊上一頭。
   * 其餘節點照常往後移一格。由 wfAdvancePhysics 每個物理小步呼叫。
   */
  function wfPushSnakeAfterTick(w, i) {
    const sb =
      typeof w.snSeg === "number" && w.snSeg > 0 ? w.snSeg | 0 : WF_SNAKE_SEG;
    const b = i * sb;
    const prevHeadLng = w.snLng[b + 0];
    const prevHeadLat = w.snLat[b + 0];
    for (let k = sb - 1; k >= 1; k--) {
      w.snLng[b + k] = w.snLng[b + k - 1];
      w.snLat[b + k] = w.snLat[b + k - 1];
    }
    const nhl = w.lngs[i];
    const nhta = w.lats[i];
    w.snLng[b + 0] = nhl;
    w.snLat[b + 0] = nhta;
    const mid = wfMidLngLat(prevHeadLng, prevHeadLat, nhl, nhta);
    w.snLng[b + 1] = mid.lng;
    w.snLat[b + 1] = mid.lat;
  }

  function wfInitParticles(w, item) {
    const tau = wfClampTau(item.flowDataTau);
    const dbgN = (w.debugMask & WF_DBG_NEAREST) !== 0;
    const n =
      typeof w.nParticles === "number" && w.nParticles > 0
        ? w.nParticles | 0
        : WF_PARTICLE_N;
    for (let i = 0; i < n; i++) {
      wfRespawnParticle(w, item, i);
    }
    wfRecomputeOcc(w);
  }

  function wfStepParticle(w, item, i, dt, tau, motionScale, debugNearest) {
    const g = w.grid;
    const lngs = w.lngs;
    const lats = w.lats;

    const olng = lngs[i];
    const olat = lats[i];

    const s0 = wfSampleUV(g, lngs[i], lats[i], tau, debugNearest);
    if (!s0.ok) {
      wfRespawnParticle(w, item, i);
      return;
    }

    const mp0 = wfMetersPerDeg(lats[i]);
    const u0s = s0.u * motionScale;
    const v0s = s0.v * motionScale;
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
      const u1s = s1.u * motionScale;
      const v1s = s1.v * motionScale;
      lngs[i] = wfWrapLongitude(lngs[i] + (u1s / mp1.mLng) * dt);
      lats[i] += (v1s / mp1.mLat) * dt;
    }

    w.travelM[i] += wfDeltaMetersLngLat(olng, olat, lngs[i], lats[i]);
    if (w.travelBudgetM[i] > 1 && w.travelM[i] >= w.travelBudgetM[i]) {
      wfRespawnParticle(w, item, i);
    }
  }

  function wfAdvancePhysics(w, item, dtLogical, tau, motionScalePre) {
    const tun = item._flowParticleTuning || wfParticleTuningSnapshot();
    const map = item.map;
    const g = w.grid;
    const motionScale =
      typeof motionScalePre === "number" && Number.isFinite(motionScalePre)
        ? motionScalePre
        : wfFlowMotionScaleCore(map, tun.advectionSpeedMul);
    const vmax = g.vmax * motionScale + tun.speedEps;
    const minCell = Math.max(g.minCellMeters, 1e-5);
    const dtSafe = (0.7 * minCell) / vmax;
    let nSub = 1;
    if (dtLogical > dtSafe && dtSafe > 1e-6) {
      nSub = Math.ceil(dtLogical / dtSafe);
      if (nSub > 64) nSub = 64;
    }
    const h = dtLogical / nSub;
    if (wfFlowAdvVerbose()) {
      let zDbg = "?";
      try {
        zDbg = map.getZoom().toFixed(2);
      } catch (_) {}
      fmpDbg(
        "[wf.advance] dtLogical=" +
          dtLogical.toFixed(6) +
          " nSub=" +
          String(nSub) +
          " h=" +
          h.toFixed(8) +
          " dtSafe=" +
          dtSafe.toFixed(6) +
          " vmax=" +
          vmax.toFixed(4) +
          " z=" +
          zDbg
      );
    }
    const dbgN = (w.debugMask & WF_DBG_NEAREST) !== 0;
    let p0aLng = NaN;
    let p0aLat = NaN;
    if (wfFlowAdvVerbose()) {
      p0aLng = w.lngs[0];
      p0aLat = w.lats[0];
    }
    const nPart =
      typeof w.nParticles === "number" && w.nParticles > 0
        ? w.nParticles | 0
        : WF_PARTICLE_N;
    for (let s = 0; s < nSub; s++) {
      for (let i = 0; i < nPart; i++) {
        wfStepParticle(w, item, i, h, tau, motionScale, dbgN);
      }
      w.snakePushSubIx = (w.snakePushSubIx | 0) + 1;
      if (w.snakePushSubIx >= tun.snakePushEveryNSub) {
        w.snakePushSubIx = 0;
        for (let si = 0; si < nPart; si++) wfPushSnakeAfterTick(w, si);
      }
    }
    if (wfFlowAdvVerbose()) {
      const dbLng = Math.abs(w.lngs[0] - p0aLng);
      const dbLat = Math.abs(w.lats[0] - p0aLat);

      fmpDbg(
        "[wf.advance.p0Δ] Δlng≈" +
          dbLng.toExponential(3) +
          " Δlat≈" +
          dbLat.toExponential(3)
      );
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
    if (map && wf.onMoveEnd) {
      try {
        map.off("moveend", wf.onMoveEnd);
      } catch (_) {}
    }
    if (map && wf.onResize) {
      try {
        map.off("resize", wf.onResize);
      } catch (_) {}
    }
    if (map && wf.onDragStart) {
      try {
        map.off("dragstart", wf.onDragStart);
      } catch (_) {}
    }
    if (map && wf.onDragEnd) {
      try {
        map.off("dragend", wf.onDragEnd);
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

  /**
   * map.project() 為 CSS 像素；overlay canvas 的繪圖座標與 map.getCanvas().width/height（裝置像素）一致，
   * 若不乘 DPR 則高解析度下粒子全擠在左上角，看起來像「沒海流」。
   */
  function wfMapProjectToCanvasBuffer(map, lng, lat) {
    const p = map.project([lng, lat]);
    const mc = map.getCanvas && map.getCanvas();
    const cw = mc && mc.clientWidth ? mc.clientWidth : 0;
    const ch = mc && mc.clientHeight ? mc.clientHeight : 0;
    if (!mc || !cw || !ch || !mc.width || !mc.height) {
      return { x: p.x, y: p.y };
    }
    const sx = mc.width / cw;
    const sy = mc.height / ch;
    return { x: p.x * sx, y: p.y * sy };
  }

  /** map buffer 座標與 CSS px 的換算（≈ devicePixelRatio × 非整比） */
  function wfCanvasBufferPxPerCss(map) {
    const mc = map.getCanvas && map.getCanvas();
    if (!mc || !mc.clientWidth || mc.clientWidth <= 0 || !mc.width) {
      return typeof window !== "undefined" && window.devicePixelRatio
        ? Math.max(1, window.devicePixelRatio)
        : 1;
    }
    return Math.max(1, mc.width / mc.clientWidth);
  }

  /**
   * 強制本幀粒子頭在「繪圖 buffer」上對「幀起點 prev」至少位移 minCss×buffer 倍率；
   * 不足時沿當地採樣流場方向追加地理步長（與 wfFlowMotionScaleCore、累積路程一致）。
   */
  function wfEnforceMinScreenStrideThisFrame(w, item, map, tau, dbgN) {
    const tun = item._flowParticleTuning || wfParticleTuningSnapshot();
    const minCss = Math.max(1, Number(tun.minFrameStrideCssPx) || 1);
    const pxBuf = minCss * wfCanvasBufferPxPerCss(map);
    const mot = wfFlowMotionScaleCore(map, tun.advectionSpeedMul);
    const g = w.grid;
    const n =
      typeof w.nParticles === "number" && w.nParticles > 0 ? w.nParticles | 0 : 0;
    const sb =
      typeof w.snSeg === "number" && w.snSeg > 0 ? w.snSeg | 0 : WF_SNAKE_SEG;

    for (let i = 0; i < n; i++) {
      let prv;
      try {
        prv = wfMapProjectToCanvasBuffer(map, w.prev_lngs[i], w.prev_lats[i]);
      } catch (_) {
        continue;
      }

      let cur;
      try {
        cur = wfMapProjectToCanvasBuffer(map, w.lngs[i], w.lats[i]);
      } catch (_) {
        continue;
      }

      let dx = cur.x - prv.x;
      let dy = cur.y - prv.y;
      if (dx * dx + dy * dy >= pxBuf * pxBuf) continue;

      const s0 = wfSampleUV(g, w.lngs[i], w.lats[i], tau, dbgN);
      if (!s0.ok) continue;

      const lngSnap = w.lngs[i];
      const latSnap = w.lats[i];
      let lng = lngSnap;
      let lat = latSnap;
      let stepSec = 18;
      for (let k = 0; k < 100; k++) {
        const mp = wfMetersPerDeg(lat);
        lng = wfWrapLongitude(lng + ((s0.u * mot) / mp.mLng) * stepSec);
        lat = lat + ((s0.v * mot) / mp.mLat) * stepSec;

        let pn;
        try {
          pn = wfMapProjectToCanvasBuffer(map, lng, lat);
        } catch (_) {
          break;
        }

        dx = pn.x - prv.x;
        dy = pn.y - prv.y;
        if (dx * dx + dy * dy >= pxBuf * pxBuf) {
          w.travelM[i] += wfDeltaMetersLngLat(lngSnap, latSnap, lng, lat);
          w.lngs[i] = lng;
          w.lats[i] = lat;
          const b = i * sb;
          w.snLng[b] = lng;
          w.snLat[b] = lat;
          break;
        }
        stepSec *= 1.1;
      }
    }
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
            const p = wfMapProjectToCanvasBuffer(map, fx, fy);
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
            const p0 = wfMapProjectToCanvasBuffer(map, lng, lat);
            const p1 = wfMapProjectToCanvasBuffer(map, lng + dLng, lat + dLat);
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

  /** 依調參尺寸配置粒子／蛇身陣列；變更 particleCount/snakeSeg 時會重置粒子分布。 */
  function wfEnsureParticleArraysMatchTuning(wf, item, tun) {
    if (!wf || !item || !tun) return;
    const needSn = tun.particleCount * tun.snakeSeg;
    if (
      typeof wf.nParticles === "number" &&
      wf.nParticles === tun.particleCount &&
      typeof wf.snSeg === "number" &&
      wf.snSeg === tun.snakeSeg &&
      wf.lngs &&
      wf.lngs.length === tun.particleCount &&
      wf.snLng &&
      wf.snLng.length === needSn
    )
      return;
    wf.nParticles = tun.particleCount;
    wf.snSeg = tun.snakeSeg;
    wf.lngs = new Float32Array(wf.nParticles);
    wf.lats = new Float32Array(wf.nParticles);
    wf.prev_lngs = new Float32Array(wf.nParticles);
    wf.prev_lats = new Float32Array(wf.nParticles);
    wf.snLng = new Float32Array(needSn);
    wf.snLat = new Float32Array(needSn);
    wf.travelM = new Float32Array(wf.nParticles);
    wf.travelBudgetM = new Float32Array(wf.nParticles);
    wfInitParticles(wf, item);
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
      const T0 = wfParticleTuningSnapshot();
      let zInit = WF_REF_ZOOM;
      try {
        zInit = map.getZoom();
      } catch (_) {}
      const nPc = wfEffectiveParticleCountForZoom(T0.particleCount, zInit);
      const nSg = T0.snakeSeg;
      wf = {
        grid,
        gridSig: sig,
        nParticles: nPc,
        snSeg: nSg,
        lngs: new Float32Array(nPc),
        lats: new Float32Array(nPc),
        prev_lngs: new Float32Array(nPc),
        prev_lats: new Float32Array(nPc),
        snLng: new Float32Array(nPc * nSg),
        snLat: new Float32Array(nPc * nSg),
        travelM: new Float32Array(nPc),
        travelBudgetM: new Float32Array(nPc),
        rng,
        occ: wfOccupancyBins(grid, 32, 26),
        lastTs: typeof performance !== "undefined" ? performance.now() : 0,
        raf: null,
        frameId: 0,
        snakePushSubIx: 0,
        canvas: null,
        dbgCanvas: null,
        ctxMain: null,
        ctxDbg: null,
        debugMask: 0,
        mapInteracting: false,
        /** Mapbox 使用者平移拖曳中：不畫粒子尾跡，但模擬照常推進。 */
        mapDragging: false,
        onMoveStart: null,
        onMoveEnd: null,
        onDragStart: null,
        onDragEnd: null,
        onResize: null,
      };
      wfInitParticles(wf, item);
      item._windyFlow = wf;
    }

    wf = item._windyFlow;
    var TwEnsure = wfParticleTuningSnapshot();
    let zEnsure = WF_REF_ZOOM;
    try {
      zEnsure = map.getZoom();
    } catch (_) {}
    TwEnsure.particleCount = wfEffectiveParticleCountForZoom(
      TwEnsure.particleCount,
      zEnsure,
    );
    item._flowParticleTuning = TwEnsure;
    if (
      typeof wf.nParticles !== "number" ||
      wf.nParticles < 8 ||
      typeof wf.snSeg !== "number" ||
      wf.snSeg < 2
    ) {
      wf.nParticles = TwEnsure.particleCount;
      wf.snSeg = TwEnsure.snakeSeg;
    }
    wfEnsureParticleArraysMatchTuning(wf, item, TwEnsure);
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
      wf.ctxMain = c.getContext("2d", { alpha: true });
      wf.ctxDbg = dc.getContext("2d", { alpha: true });

      wf.onMoveStart = function () {
        wf.mapInteracting = true;
        wfSyncFlowCanvasSize(map, wf.canvas);
        wfSyncFlowCanvasSize(map, wf.dbgCanvas);
      };
      wf.onMoveEnd = function () {
        wf.mapInteracting = false;
        wfSyncFlowCanvasSize(map, wf.canvas);
        wfSyncFlowCanvasSize(map, wf.dbgCanvas);
      };
      wf.onResize = function () {
        wfSyncFlowCanvasSize(map, wf.canvas);
        wfSyncFlowCanvasSize(map, wf.dbgCanvas);
      };
      wf.onDragStart = function () {
        wf.mapDragging = true;
      };
      wf.onDragEnd = function () {
        wf.mapDragging = false;
      };
      map.on("movestart", wf.onMoveStart);
      map.on("moveend", wf.onMoveEnd);
      map.on("dragstart", wf.onDragStart);
      map.on("dragend", wf.onDragEnd);
      map.on("resize", wf.onResize);
      fmpDbg("[wfEnsureWindyFlow] flow canvas DOM attached");
    }

    if (wf.raf == null) {
      wf.lastTs = typeof performance !== "undefined" ? performance.now() : 0;
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

        const tunTick = wfParticleTuningSnapshot();
        item._flowParticleTuning = tunTick;
        wfEnsureParticleArraysMatchTuning(wf2, item, tunTick);

        let ctx = wf2.ctxMain;
        if (!ctx)
          wf2.ctxMain =
            ctx =
              wf2.canvas.getContext("2d", {
                alpha: true,
                desynchronized: true,
              }) || wf2.canvas.getContext("2d", { alpha: true });
        let ctxDbg = wf2.ctxDbg;
        if (!ctxDbg)
          wf2.ctxDbg =
            ctxDbg =
              wf2.dbgCanvas.getContext("2d", {
                alpha: true,
                desynchronized: true,
              }) || wf2.dbgCanvas.getContext("2d", { alpha: true });
        wfSyncFlowCanvasSize(map, wf2.canvas);
        wfSyncFlowCanvasSize(map, wf2.dbgCanvas);

        const tau = wfClampTau(item.flowDataTau);
        let dtWall = 0;
        if (wf2.lastTs > 0) {
          dtWall = Math.min(0.12, Math.max(0, (now - wf2.lastTs) / 1000));
        }
        wf2.lastTs = now;

        // 繪製用 prev：每幀 RAF tick 只快照一次（本幀物理前）。若沿用 wfStepParticle 內每子步寫 prev，
        // multi-substep 後 prev 只會落在「最後一小步起點」，視覺上線段極短、像不會動。
        const nPcTick = wf2.nParticles | 0;
        for (let pi = 0; pi < nPcTick; pi++) {
          wf2.prev_lngs[pi] = wf2.lngs[pi];
          wf2.prev_lats[pi] = wf2.lats[pi];
        }

        const fac = tunTick.animFactor;
        const dtSimT = tunTick.dtSim;
        const rawWall =
          dtWall > 1e-7 ? dtWall : 1 / 120;
        let simRem = rawWall * fac;
        simRem = Math.min(
          Math.max(simRem, dtSimT * tunTick.simWallMinFrac),
          dtSimT * tunTick.simWallMaxMul,
        );
        const simAtTickStart = simRem;

        const motionScaleThisFrame = wfFlowMotionScaleCore(
          map,
          tunTick.advectionSpeedMul,
        );

        let advSlices = 0;

        while (simRem > 1e-12) {
          const slice = Math.min(dtSimT, simRem);
          wfAdvancePhysics(wf2, item, slice, tau, motionScaleThisFrame);
          simRem -= slice;
          advSlices++;
          if (advSlices > 5000) {
            fmpDbg("[wf.tick] abort advSlices cap rem=" + String(simRem));
            break;
          }
        }

        const dbgStride = (wf2.debugMask & WF_DBG_NEAREST) !== 0;
        wfEnforceMinScreenStrideThisFrame(wf2, item, map, tau, dbgStride);

        let zTxt = "?";
        try {
          zTxt = map.getZoom().toFixed(2);
        } catch (_) {}
        let mSum = 0;
        let mN = 0;
        const mStep = Math.max(1, (nPcTick / 48) | 0);
        for (let mj = 0; mj < nPcTick; mj += mStep) {
          mSum +=
            Math.abs(wf2.lngs[mj] - wf2.prev_lngs[mj]) +
            Math.abs(wf2.lats[mj] - wf2.prev_lats[mj]);
          mN++;
        }

        if (wfFlowTickDbg()) {
          fmpDbg(
            "[wf.tick] dtWall=" +
              dtWall.toFixed(6) +
              " animFac=" +
              String(fac) +
              " simRemClamped(start)=" +
              simAtTickStart.toFixed(4) +
              " slicesDone=" +
              String(advSlices) +
              " mean|dλ|+|dφ|=" +
              (mN ? (mSum / mN).toExponential(4) : "0") +
              " z=" +
              zTxt +
              " (advance: globalThis." +
              WF_ADV_VERBOSE_FLAG +
              "=true)"
          );
        }

        const noFade = (wf2.debugMask & WF_DBG_NO_FADE) !== 0;
        if (!noFade) {
          ctx.globalCompositeOperation = "destination-in";
          ctx.fillStyle =
            "rgba(" +
              0 +
              "," +
              0 +
              "," +
              0 +
              "," +
              tunTick.fadeAlpha +
              ")";
          ctx.fillRect(0, 0, wf2.canvas.width, wf2.canvas.height);
          ctx.globalCompositeOperation = "source-over";
        } else {
          ctx.clearRect(0, 0, wf2.canvas.width, wf2.canvas.height);
        }

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
        const mcDraw = map.getCanvas && map.getCanvas();
        const cwDraw =
          mcDraw && mcDraw.clientWidth ? mcDraw.clientWidth : wf2.canvas.width;
        const bufScaleJump = Math.max(
          wf2.canvas.width / Math.max(1, cwDraw),
          1,
        );
        /** 過小時蛇身第一段即超距 → 頂點不足 2 個只能畫上一幀短線，看起來碎、不連續 */
        const maxJumpBuf = bufScaleJump * Math.max(2200, cwDraw * 1.6);
        const minLenBuf = wfMinStrokeBufPxFor(map, tunTick.minStrokeCssPx);
        const sbSn =
          typeof wf2.snSeg === "number" && wf2.snSeg > 0
            ? wf2.snSeg | 0
            : tunTick.snakeSeg | 0;
        const bufScale = Math.max(wf2.canvas.width / Math.max(1, cwDraw), 1);
        const meteorLinePx = Math.min(
          tunTick.lineDrawMaxBuf,
          Math.max(
            tunTick.lineDrawMinBuf,
            tunTick.lineWidth * bufScale * 1.08,
          ),
        );

        /** 平移拖曳中不描新尾跡（仍做 destination-in，舊痕會淡出）；慣性平移會恢復描繪。 */
        const suppressTrailsDrag = !!(wf2 && wf2.mapDragging);

        if (!suppressTrailsDrag) {
        for (let i = 0; i < nPcTick; i++) {
          if (tracerOnly && i !== 0) continue;
          const lngHead = wf2.lngs[i];
          const latHead = wf2.lats[i];
          if (lngHead < west || lngHead > east || latHead < south || latHead > north)
            continue;

          let headPx = null;
          try {
            headPx = wfMapProjectToCanvasBuffer(map, lngHead, latHead);
          } catch (_) {
            continue;
          }

          let sHead = wfSampleUV(wf2.grid, lngHead, latHead, tau, dbgNearest);
          let spd = sHead.ok ? Math.hypot(sHead.u, sHead.v) : 0;
          const li = wfSpeedToLutIdx(spd);
          const o = li * 4;

          const sbIdx = i * sbSn;
          try {
            let pathDeg = 0;
            const pts = [];
            let prevLng = wf2.snLng[sbIdx + 0];
            let prevLat = wf2.snLat[sbIdx + 0];
            let pPrev = wfMapProjectToCanvasBuffer(map, prevLng, prevLat);
            pts.push(pPrev);
            for (let k = 1; k < sbSn; k++) {
              const lngK = wf2.snLng[sbIdx + k];
              const latK = wf2.snLat[sbIdx + k];
              const dDeg = wfSnakeDegDelta(prevLng, prevLat, lngK, latK);
              if (!Number.isFinite(dDeg) || dDeg > 80) break;
              pathDeg += dDeg;
              const pk = wfMapProjectToCanvasBuffer(map, lngK, latK);
              const ddx = pk.x - pPrev.x;
              const ddy = pk.y - pPrev.y;
              if (ddx * ddx + ddy * ddy > maxJumpBuf * maxJumpBuf) break;
              pts.push(pk);
              prevLng = lngK;
              prevLat = latK;
              pPrev = pk;
              if (
                pathDeg > tunTick.snakeAbsMaxPathDeg + 1e-6
              )
                break;
              if (
                pathDeg > tunTick.snakeMaxPathDeg + 1e-6 &&
                pts.length >= tunTick.snakeMinDrawVerts
              )
                break;
            }

            /** 避免因跳距／裁剪過 early 退回「僅頭↔上一幀」火花感；至少連到蛇身索引 1 */
            if (
              pts.length < 2 &&
              sbSn >= 2 &&
              Number.isFinite(wf2.snLng[sbIdx + 1]) &&
              Number.isFinite(wf2.snLat[sbIdx + 1])
            ) {
              try {
                pts.push(
                  wfMapProjectToCanvasBuffer(
                    map,
                    wf2.snLng[sbIdx + 1],
                    wf2.snLat[sbIdx + 1],
                  ),
                );
              } catch (_) {}
            }

            try {
              const lngP = wf2.prev_lngs[i];
              const latP = wf2.prev_lats[i];
              if (Math.abs(lngHead - lngP) <= 180)
                pts.push(wfMapProjectToCanvasBuffer(map, lngP, latP));
            } catch (_) {}
            let verts = wfDedupePxChain(pts, 0.42);

            if (verts.length < 2) {
              const lng0 = wf2.prev_lngs[i];
              const lat0 = wf2.prev_lats[i];
              if (Math.abs(lngHead - lng0) <= 180) {
                try {
                  const p0 = wfMapProjectToCanvasBuffer(map, lng0, lat0);
                  const p1 = wfMapProjectToCanvasBuffer(map, lngHead, latHead);
                  let dx = p1.x - p0.x;
                  let dy = p1.y - p0.y;
                  const len2 = dx * dx + dy * dy;
                  if (len2 <= maxJumpBuf * maxJumpBuf && len2 > 1e-12) {
                    let len = Math.sqrt(len2);
                    if (len < minLenBuf) {
                      const s = minLenBuf / len;
                      dx *= s;
                      dy *= s;
                    }
                    verts = [p0, { x: p0.x + dx, y: p0.y + dy }];
                  } else if (len2 <= maxJumpBuf * maxJumpBuf) {
                    verts = [p0, p1];
                  }
                  verts = wfDedupePxChain(verts, 0.25);
                } catch (_) {}
              }
            }

            if (verts.length < 2) {
              verts = [
                { x: headPx.x, y: headPx.y },
                { x: headPx.x + 0.15, y: headPx.y + 0.15 },
              ];
            }

            let drawVerts = verts;
            if (
              drawVerts.length >= 2 &&
              drawVerts.length < tunTick.snakeMinDrawVerts
            ) {
              const hed = drawVerts[0];
              const tal = drawVerts[drawVerts.length - 1];
              const dv = tunTick.snakeMinDrawVerts;
              const dense = [];
              for (let c = 0; c < dv; c++) {
                const t =
                  dv <= 1 ? 0 : c / Math.max(1e-9, dv - 1);
                dense.push({
                  x: tal.x + (hed.x - tal.x) * t,
                  y: tal.y + (hed.y - tal.y) * t,
                });
              }
              drawVerts = dense;
            }

            let stripFh = wfTailToHeadStrip(drawVerts, headPx);
            stripFh = wfEnsureMinStreakExtent(
              map,
              headPx,
              stripFh,
              minLenBuf * 1.04,
              lngHead,
              latHead,
              wf2.grid,
              tau,
              dbgNearest,
            );
            wfStrokeMeteorTrail(
              ctx,
              stripFh,
              headPx,
              o,
              meteorLinePx,
              tunTick.meteorShadowBlur,
              tunTick.headCapMul,
            );
          } catch (_) {}
        }
        }

        ctxDbg.clearRect(0, 0, wf2.dbgCanvas.width, wf2.dbgCanvas.height);
        if (
          !wfMapIsInteracting(map, wf2) &&
          (wf2.debugMask & (WF_DBG_ARROWS | WF_DBG_GRID)) !== 0
        ) {
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

  function spotsSourceSpec(data) {
    return {
      type: "geojson",
      data,
      cluster: true,
      clusterMaxZoom: SPOT_CLUSTER_MAX_ZOOM,
      clusterRadius: SPOT_CLUSTER_RADIUS,
      clusterMinPoints: 2,
      clusterProperties: {
        poiN: [
          "+",
          ["case", ["==", ["get", "entryKind"], "fishingPoi"], 1, 0],
        ],
        shrN: [
          "+",
          ["case", ["==", ["get", "entryKind"], "conditionShare"], 1, 0],
        ],
      },
    };
  }

  /** 釣點 moveLayer 後將測站圖層拉回其上，避免叢集圓／釣點 symbol 蓋住潮位／浮標圖示。 */
  function reorderSpotAndCwaLayers(map) {
    const spotsOrder = [
      "spots-clusters",
      "spots-cluster-icons",
      "spots-cluster-count",
      "spots-unclustered",
    ];
    for (var si = 0; si < spotsOrder.length; si++) {
      const sid = spotsOrder[si];
      if (map.getLayer(sid)) {
        try {
          map.moveLayer(sid);
        } catch (_) {}
      }
    }
    const cwaStack = [
      "cwa-tide-clusters",
      "cwa-tide-cluster-icons",
      "cwa-tide-unclustered",
      "cwa-tide-label",
      "cwa-buoy-clusters",
      "cwa-buoy-cluster-icons",
      "cwa-buoy-unclustered",
      "cwa-buoy-label",
    ];
    for (var ci = 0; ci < cwaStack.length; ci++) {
      const cid = cwaStack[ci];
      if (map.getLayer(cid)) {
        try {
          map.moveLayer(cid);
        } catch (_) {}
      }
    }
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
    ensureSpotMarkerImagesLoaded(map, function syncSpotsSymbolLayers() {
      const sci = map.getLayer("spots-cluster-icons");
      if (sci && sci.type !== "symbol") {
        try {
          map.removeLayer("spots-cluster-icons");
        } catch (_) {}
      }
      if (!map.getLayer("spots-cluster-icons")) {
        map.addLayer({
          id: "spots-cluster-icons",
          type: "symbol",
          source: "spots",
          filter: ["has", "point_count"],
          layout: {
            "icon-image": [
              "case",
              [">", ["coalesce", ["get", "poiN"], 0], 0],
              [
                "case",
                [">", ["coalesce", ["get", "shrN"], 0], 0],
                [
                  "case",
                  [
                    ">=",
                    ["coalesce", ["get", "poiN"], 0],
                    ["coalesce", ["get", "shrN"], 0],
                  ],
                  "spot-icon-fishing-poi",
                  "spot-icon-condition-share",
                ],
                "spot-icon-fishing-poi",
              ],
              "spot-icon-condition-share",
            ],
            "icon-size": 0.56,
            "icon-allow-overlap": true,
            "icon-ignore-placement": true,
          },
        });
      }
      const ul = map.getLayer("spots-unclustered");
      if (ul && ul.type !== "symbol") {
        try {
          map.removeLayer("spots-unclustered");
        } catch (_) {}
      }
      if (!map.getLayer("spots-unclustered")) {
        map.addLayer({
          id: "spots-unclustered",
          type: "symbol",
          source: "spots",
          filter: ["!", ["has", "point_count"]],
          layout: {
            "icon-image": [
              "match",
              ["get", "entryKind"],
              "fishingPoi",
              "spot-icon-fishing-poi",
              "conditionShare",
              "spot-icon-condition-share",
              "spot-icon-condition-share",
            ],
            "icon-size": 1.02,
            "icon-allow-overlap": true,
            "icon-ignore-placement": true,
          },
        });
      }
      reorderSpotAndCwaLayers(map);
    });
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
      layerId === "spots-cluster-icons" ||
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
      "spots-cluster-icons",
      "spots-clusters",
      "cwa-tide-cluster-icons",
      "cwa-tide-unclustered",
      "cwa-tide-clusters",
      "cwa-buoy-cluster-icons",
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

      const fcSpots = toFeatureCollection(spots);
      const source = map.getSource("spots");
      if (!source) {
        try {
          map.addSource("spots", spotsSourceSpec(fcSpots));
        } catch (_) {}
      } else if (typeof source.setData === "function") {
        source.setData(fcSpots);
      }
      ensureSpotClusterLayers(map);
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

  window.flowParticleTuningResetDefaults = function () {
    const d = wfParticleTuningBuiltinDefaults();
    wfBootstrapFlowParticleTuning();
    const t = globalThis.fishingFlowParticleTuning;
    for (const k in d) t[k] = d[k];
  };

  /** 載入／重設後保證全域物件存在 */
  wfBootstrapFlowParticleTuning();

  function wfInstallParticleTuningPanelOnce() {
    if (typeof document === "undefined") return;
    if (!WF_PARTICLE_TUNING_PANEL_UI) return;
    if (document.getElementById("ffp-tuning-shell")) return;

    const spec = [
      ["animFactor", "動畫係數（牆鐘換算流速）", 8, 720, 4],
      [
        "particleCount",
        "粒子數底數（zoom≈" +
          String(WF_REF_ZOOM) +
          " 為 1×，放大地圖自動加量）",
        50,
        10000,
        25,
      ],
      ["minStrokeCssPx", "最短筆畫 CSS px", 0.5, 36, 0.25],
      ["minFrameStrideCssPx", "每幀至少位移(CSS px)→buffer", 1, 12, 0.25],
      ["advectionSpeedMul", "沿流平流倍率(u,v)", 0.15, 24, 0.05],
      ["fadeAlpha", "軌跡淡出(愈大尾巴愈久)", 0.35, 0.995, 0.005],
      ["lineWidth", "流星線寬基準", 0.5, 22, 0.25],
      ["meteorShadowBlur", "外發光強度(blur)", 0, 52, 1],
      ["headCapMul", "頭部圓帽 × 線寬", 0, 5, 0.05],
      ["lineDrawMinBuf", "線寬下限(buffer px)", 0.3, 30, 0.1],
      ["lineDrawMaxBuf", "線寬上限(buffer px)", 1, 72, 0.5],
      ["snakeSeg", "蛇身分節數", 2, 64, 1],
      ["snakeMaxPathDeg", "蛇身長度軟上限(度)", 0.02, 8, 0.02],
      ["snakeAbsMaxPathDeg", "蛇身長度硬上限(度)", 0.05, 12, 0.05],
      ["snakeMinDrawVerts", "最少繪製頂點數", 2, 24, 1],
      ["snakePushEveryNSub", "每幾個子步推入蛇鏈", 1, 20, 1],
      [
        "travelBudgetMinM",
        "路徑長度下限（公尺）後重生",
        2000,
        120000,
        500,
      ],
      [
        "travelBudgetExtraM",
        "外加隨機長度（公尺）0～此值",
        0,
        200000,
        1000,
      ],
      ["simWallMinFrac", "每幀模擬下限×dtSim", 0.01, 1.5, 0.01],
      ["simWallMaxMul", "每幀模擬上限倍數×dtSim", 1, 400, 1],
      ["dtSim", "物理切片 dtSim(秒)", 0.15, 16, 0.05],
      ["speedEps", "速度 eps(CFL)", 0.001, 4, 0.001],
    ];

    const shell = document.createElement("div");
    shell.id = "ffp-tuning-shell";
    shell.setAttribute("aria-label", "海流粒子調參");
    shell.style.cssText =
      "position:fixed;inset:0;pointer-events:none;z-index:2147483646;";

    const fab = document.createElement("button");
    fab.type = "button";
    fab.textContent = "粒子調參";
    fab.style.cssText =
      "position:fixed;right:14px;bottom:14px;z-index:1;pointer-events:auto;padding:10px 12px;font-size:13px;font-weight:600;font-family:system-ui,Segoe UI,sans-serif;border-radius:10px;border:1px solid #334155;background:#0f172a;color:#e2e8f0;cursor:pointer;box-shadow:0 4px 14px rgba(0,0,0,.35);";

    const panel = document.createElement("div");
    panel.id = "ffp-tuning-panel";
    panel.style.cssText =
      "display:none;position:fixed;right:14px;bottom:54px;width:min(360px,calc(100vw - 28px));max-height:72vh;overflow:auto;z-index:1;pointer-events:auto;background:#0f172a;color:#e2e8f0;font:13px/1.4 system-ui,Segoe UI,sans-serif;border-radius:12px;border:1px solid #334155;box-shadow:0 12px 40px rgba(0,0,0,.45);padding:12px 14px;margin-bottom:6px;";
    panel.innerHTML =
      "<div style='display:flex;align-items:flex-start;justify-content:space-between;gap:8px;margin-bottom:10px'>" +
      "<strong style='font-size:14px;line-height:1.3;color:#fff'>海流流星粒子調參</strong>" +
      "<span style='font-size:11px;color:#94a3b8'>即時套用 · 調 particleCount/snakeSeg 會重置之 · 實際粒子數隨 zoom 在 50～10000 內增減</span>" +
      "</div>" +
      "<div style='font-size:11px;color:#cbd5e1;margin-bottom:8px'>" +
      "數值來自 <code style='background:#1e293b;padding:2px 4px;border-radius:4px'>globalThis.fishingFlowParticleTuning</code>" +
      "</div>";

    const form = document.createElement("div");
    form.style.cssText = "display:flex;flex-direction:column;gap:6px";

    const inputs = {};

    function readT() {
      return globalThis.fishingFlowParticleTuning || wfParticleTuningBuiltinDefaults();
    }

    function applyInput(key, val) {
      wfBootstrapFlowParticleTuning();
      globalThis.fishingFlowParticleTuning[key] =
        typeof val === "number" && !Number.isNaN(val) ? val : 0;
      const rng = inputs[key];
      if (rng) {
        const lab = rng._labelSpan;
        if (lab) {
          const n = Number(val);
          if (!Number.isFinite(n)) lab.textContent = "";
          else if (key === "speedEps" || (Math.abs(n) < 0.01 && n !== 0))
            lab.textContent = n.toPrecision(3);
          else if (
            key === "dtSim" ||
            key === "minStrokeCssPx" ||
            key.indexOf("Deg") >= 0
          )
            lab.textContent = n.toFixed(4);
          else if (Number.isInteger(n)) lab.textContent = String(Math.round(n));
          else lab.textContent = n.toFixed(2);
        }
      }
    }

    const snapInit = wfParticleTuningSnapshot();

    spec.forEach(function (row) {
      const key = row[0];
      const zh = row[1];
      const lo = row[2];
      const hi = row[3];
      const step = row[4];

      const rowEl = document.createElement("label");
      rowEl.style.cssText =
        "display:grid;grid-template-columns:1fr auto;gap:8px 10px;align-items:center;background:#111827;border-radius:8px;padding:6px 8px;border:1px solid #1e293b";

      const top = document.createElement("span");
      top.style.cssText = "font-size:12px;color:#cbd5e1";
      top.textContent = zh;

      const valSpan = document.createElement("span");
      valSpan.style.cssText = "font-variant-numeric:tabular-nums;color:#fff;font-size:12px";

      const rng = document.createElement("input");
      rng.type = "range";
      rng.min = String(lo);
      rng.max = String(hi);
      rng.step = String(step);
      rng.value = String(snapInit[key]);
      rng.style.gridColumn = "1 / span 2";
      rng.style.width = "100%";
      rng._labelSpan = valSpan;

      rng.addEventListener("input", function () {
        applyInput(key, Number(rng.value));
      });

      inputs[key] = rng;
      applyInput(key, Number(rng.value));

      rowEl.appendChild(top);
      rowEl.appendChild(valSpan);
      rowEl.appendChild(rng);
      form.appendChild(rowEl);
    });

    const btnRow = document.createElement("div");
    btnRow.style.cssText =
      "display:flex;flex-wrap:wrap;gap:8px;margin-top:10px;padding-top:10px;border-top:1px solid #334155";

    const btnReset = document.createElement("button");
    btnReset.type = "button";
    btnReset.textContent = "還原內建預設";
    btnReset.style.cssText =
      "pointer-events:auto;flex:1;min-width:120px;padding:8px;border-radius:8px;border:1px solid #475569;background:#1e293b;color:#e2e8f0;cursor:pointer;font-size:12px;";
    btnReset.onclick = function () {
      window.flowParticleTuningResetDefaults();
      const t = readT();
      spec.forEach(function (row) {
        const key = row[0];
        if (inputs[key]) {
          inputs[key].value = String(t[key]);
          applyInput(key, Number(inputs[key].value));
        }
      });
    };

    const btnFold = document.createElement("button");
    btnFold.type = "button";
    btnFold.textContent = "關閉";
    btnFold.style.cssText =
      "pointer-events:auto;padding:8px 12px;border-radius:8px;border:1px solid #475569;background:#1e293b;color:#e2e8f0;cursor:pointer;font-size:12px;";

    btnRow.appendChild(btnReset);
    btnRow.appendChild(btnFold);

    panel.appendChild(form);
    panel.appendChild(btnRow);

    btnFold.onclick = function () {
      panel.style.display = "none";
    };

    fab.onclick = function () {
      panel.style.display = panel.style.display === "none" ? "block" : "none";
    };

    shell.appendChild(panel);
    shell.appendChild(fab);
    document.body.appendChild(shell);

    window.flowParticleTuningPanelToggle = function (show) {
      if (!panel) return;
      if (show === undefined) {
        panel.style.display = panel.style.display === "none" ? "block" : "none";
      } else {
        panel.style.display = show ? "block" : "none";
      }
    };

    /** 與調參器同步（例如程式改了大寫）： */
    window.flowParticleTuningSyncSliders = function () {
      const t = wfParticleTuningSnapshot();
      spec.forEach(function (row) {
        const key = row[0];
        if (inputs[key]) {
          inputs[key].value = String(t[key]);
          applyInput(key, t[key]);
        }
      });
    };
  }

  if (typeof document !== "undefined") {
    if (document.readyState === "loading") {
      document.addEventListener(
        "DOMContentLoaded",
        wfInstallParticleTuningPanelOnce,
      );
    } else {
      wfInstallParticleTuningPanelOnce();
    }
  }
})();
