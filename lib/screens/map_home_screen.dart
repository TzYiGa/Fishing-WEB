import "dart:async";

import "package:fishing_map/data/cwa_station_loader.dart";
import "package:fishing_map/services/copernicus_ocean_vector_service.dart";
import "package:fishing_map/models/cwa_station_point.dart";
import "package:fishing_map/models/fishing_spot.dart";
import "package:fishing_map/models/spot_category.dart";
import "package:fishing_map/models/map_view_settings.dart";
import "package:fishing_map/screens/auth_popup_panel.dart";
import "package:fishing_map/screens/map_settings_screen.dart";
import "package:fishing_map/services/auth_service.dart";
import "package:fishing_map/services/spot_repository.dart";
import "package:fishing_map/services/user_settings_repository.dart";
import "package:fishing_map/widgets/add_spot_sheet.dart";
import "package:fishing_map/widgets/fishing_map_view.dart";
import "package:fishing_map/widgets/admin_web_action_debug_panel.dart";
import "package:fishing_map/widgets/mapbox_interaction_overlay.dart";
import "package:fishing_map/widgets/spot_category_filter_panel.dart";
import "package:fishing_map/services/web_action_debug_log.dart";
import "package:fishing_map/widgets/web_admin_debug_sink.dart";
import "package:fishing_map/widgets/spot_detail_sheet.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_map/flutter_map.dart";
import "package:latlong2/latlong.dart";
import "package:pointer_interceptor/pointer_interceptor.dart";
import "package:shared_preferences/shared_preferences.dart";

class MapHomeScreen extends StatefulWidget {
  const MapHomeScreen({
    super.key,
    required this.auth,
    required this.repo,
    required this.settingsListenable,
  });

  final AuthService auth;
  final SpotRepository repo;
  final ValueNotifier<MapViewSettings> settingsListenable;

  @override
  State<MapHomeScreen> createState() => _MapHomeScreenState();
}

class _MapHomeScreenState extends State<MapHomeScreen> {
  static const _guestLanguageKey = "guest.map.language";
  static const _guestStyleKey = "guest.map.style";

  final _mapCtrl = MapController();
  final _settingsRepo = UserSettingsRepository();
  bool _pickMode = false;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<FishingSpot>>? _spotsSub;
  List<FishingSpot> _spots = const [];
  List<CwaStationPoint> _cwaStations = const [];
  bool _showCwaTide = true;
  bool _showCwaBuoy = true;
  /// Web Mapbox：WINDY SPEC v2 海流粒子層開關（資料見 [_oceanFlowJsonT0]／τ）。
  bool _showOceanCurrent = false;
  String _oceanFlowJsonT0 =
      CopernicusOceanVectorService.emptyFeatureCollectionJson;
  /// 空字串＝與 T0 相同（單時次）；雙時次時填入 T1 的 GeoJSON。
  String _oceanFlowJsonT1 = "";
  /// T_data 與仿真／繪製共用之 τ∈[0,1]（時間線性插值）。
  double _oceanFlowTau = 0;
  final _oceanVectors = CopernicusOceanVectorService();
  ExpansibleController? _filterExpansionController;
  bool _filterPanelExpanded = false;
  /// 白名單：僅顯示勾選之類型對應的釣點。
  Set<String> _visibleCategoryIds = {for (final o in kSpotCategoryOptions) o.id};
  String? _activeUid;
  bool _applyingRemoteSettings = false;

  List<FishingSpot> get _visibleSpots =>
      _spots.where((s) => _visibleCategoryIds.contains(s.categoryId)).toList();

  @override
  void initState() {
    super.initState();
    // 須早於子樹（MapboxWebCanvas）內向 JS 送 create/update，否則 fmpDbg 尚無 globalThis.fishingMapDartDebug。
    if (kIsWeb) {
      installWebAdminDebugSink(WebActionDebugLog.instance.append);
      WebActionDebugLog.instance.append("[MapHome] web JS debug sink installed (early)");
    }
    _spots = widget.repo.spotsSnapshotIfLoaded();
    widget.settingsListenable.addListener(_persistSettingsForUser);
    widget.auth.guestModeListenable.addListener(_onGuestModeChanged);
    _authSub = widget.auth.authChanges.listen(_onAuthChanged);
    _onAuthChanged(widget.auth.currentUser);
    _spotsSub = widget.repo.watchSpots().listen((list) {
      if (mounted) setState(() => _spots = list);
    });
    if (!kIsWeb) {
      _filterExpansionController = ExpansibleController();
    }
    _loadCwaStations();
    if (kIsWeb) {
      unawaited(_prefetchOceanFlowJsonForWeb());
    }
  }

  /// Web：預載 Copernicus 線段 GeoJSON → JS 側建欧拉格網／雙線性取樣。
  Future<void> _prefetchOceanFlowJsonForWeb() async {
    try {
      final j = await _oceanVectors.buildFeatureCollectionJson();
      if (!mounted) return;
      if (kIsWeb) {
        WebActionDebugLog.instance.append(
          "[ocean] prefetch done jsonLen=${j.length}",
        );
      }
      setState(() => _oceanFlowJsonT0 = j);
    } catch (e) {
      if (!mounted || !kIsWeb) return;
      WebActionDebugLog.instance.append("[ocean] prefetch error $e");
    }
  }

  Future<void> _refreshOceanFlowField() async {
    if (!_showOceanCurrent || !kIsWeb) return;
    WebActionDebugLog.instance.append("[ocean] refresh start");
    try {
      final j = await _oceanVectors.buildFeatureCollectionJson();
      if (!mounted) return;
      WebActionDebugLog.instance.append(
        "[ocean] refresh ok jsonLen=${j.length}",
      );
      setState(() => _oceanFlowJsonT0 = j);
    } catch (e) {
      if (!mounted) return;
      WebActionDebugLog.instance.append("[ocean] refresh error $e");
      setState(
        () =>
            _oceanFlowJsonT0 = CopernicusOceanVectorService.emptyFeatureCollectionJson,
      );
    }
  }

  Future<void> _loadCwaStations() async {
    try {
      final list = await loadCwaStationPointsFromAsset();
      if (!mounted) return;
      setState(() => _cwaStations = list);
    } catch (_) {
      // 資產缺失或格式異常時略過，不阻斷地圖。
    }
  }

  Future<void> _onAuthChanged(User? user) async {
    final uid = user?.uid;
    _activeUid = uid;
    if (uid == null) {
      await _onGuestModeChanged();
      return;
    }
    final loaded = await _settingsRepo.loadMapSettings(uid);
    if (!mounted || _activeUid != uid) return;
    _applyingRemoteSettings = true;
    widget.settingsListenable.value = loaded;
    _applyingRemoteSettings = false;
  }

  Future<void> _persistSettingsForUser() async {
    if (_applyingRemoteSettings) return;
    final user = widget.auth.currentUser;
    if (user != null) {
      await _settingsRepo.saveMapSettings(user.uid, widget.settingsListenable.value);
      return;
    }
    if (!widget.auth.isGuestMode) return;
    await _saveGuestSettings(widget.settingsListenable.value);
  }

  Future<void> _onGuestModeChanged() async {
    if (!mounted || _activeUid != null) return;
    if (!widget.auth.isGuestMode) {
      widget.settingsListenable.value = const MapViewSettings();
      return;
    }
    final local = await _loadGuestSettings();
    if (!mounted || _activeUid != null || !widget.auth.isGuestMode) return;
    widget.settingsListenable.value = local;
  }

  Future<MapViewSettings> _loadGuestSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final languageName = prefs.getString(_guestLanguageKey);
    final styleName = prefs.getString(_guestStyleKey);

    MapLabelLanguage language = MapLabelLanguage.traditionalChinese;
    for (final candidate in MapLabelLanguage.values) {
      if (candidate.name == languageName) {
        language = candidate;
        break;
      }
    }

    MapVisualStyle style = MapVisualStyle.outdoors;
    for (final candidate in MapVisualStyle.values) {
      if (candidate.name == styleName) {
        style = candidate;
        break;
      }
    }

    return MapViewSettings(language: language, style: style);
  }

  Future<void> _saveGuestSettings(MapViewSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_guestLanguageKey, settings.language.name);
    await prefs.setString(_guestStyleKey, settings.style.name);
  }

  @override
  void dispose() {
    if (_filterPanelExpanded) {
      _filterPanelExpanded = false;
      popMapboxInteractionBlock();
    }
    _filterExpansionController?.dispose();
    _authSub?.cancel();
    _spotsSub?.cancel();
    widget.settingsListenable.removeListener(_persistSettingsForUser);
    widget.auth.guestModeListenable.removeListener(_onGuestModeChanged);
    if (kIsWeb) {
      uninstallWebAdminDebugSink();
    }
    super.dispose();
  }

  Future<void> _togglePickMode(BuildContext ctx) async {
    if (widget.auth.currentUser == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text("請先登入再加入釣點")),
      );
      return;
    }
    setState(() => _pickMode = !_pickMode);
    if (_pickMode && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text("在地圖上點選釣點位置"),
          duration: Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _onMapPick(LatLng latlng, BuildContext ctx) async {
    if (!_pickMode) return;
    setState(() => _pickMode = false);
    if (!mounted) return;
    final ok = await AddSpotSheet.open(
      ctx,
      pick: latlng,
      repo: widget.repo,
      auth: widget.auth,
      mapLanguage: widget.settingsListenable.value.language,
    );
    if (!mounted || ok != true) return;
    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("已新增釣點")));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (kIsWeb) return;
      try {
        _mapCtrl.move(latlng, 14);
      } catch (_) {
        // Web 使用 Mapbox GL、未掛上 FlutterMap；或首幀前呼叫 move 時會拋錯，略過即可。
      }
    });
  }

  Widget _fishingMapFill() {
    return FishingMapView(
      pickMode: _pickMode,
      mapController: _mapCtrl,
      spots: _visibleSpots,
      cwaStations: _cwaStations,
      showCwaTide: _showCwaTide,
      showCwaBuoy: _showCwaBuoy,
      showOceanFlow: _showOceanCurrent && kIsWeb,
      oceanFlowGeoJsonT0: _oceanFlowJsonT0,
      oceanFlowGeoJsonT1: _oceanFlowJsonT1,
      oceanFlowDataTau: _oceanFlowTau,
      settingsListenable: widget.settingsListenable,
      onSpotTap: (s) =>
          SpotDetailSheet.open(context, spot: s, repo: widget.repo, auth: widget.auth),
      onTapAt: (lng) => _onMapPick(lng, context),
    );
  }

  /// Web：全幅地圖 + 左上角浮層篩選（可捲動、限高）。
  /// 若用 [Row] 左欄／右欄，左欄只佔篩選卡片寬度，其「下方」沒有 Flutter 子項，會整片露出 Scaffold 底色（看起來像地圖沒鋪滿）。
  /// [PointerInterceptor] 讓篩選區能點，避免底層 Mapbox [HtmlElementView] 搶事件。
  Widget _buildWebBody(BuildContext context, double safeLeft) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideMaxH = constraints.maxHeight > 120
            ? (constraints.maxHeight - 16).clamp(120.0, double.infinity)
            : 280.0;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            _fishingMapFill(),
            Positioned(
              left: safeLeft + 8,
              top: 8,
              child: PointerInterceptor(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 272, maxHeight: sideMaxH),
                  child: SingleChildScrollView(
                    primary: false,
                    clipBehavior: Clip.hardEdge,
                    child: SpotCategoryFilterPanel(
                      visibleIds: _visibleCategoryIds,
                      onVisibleIdsChanged: (next) =>
                          setState(() => _visibleCategoryIds = next),
                      showCwaTide: _showCwaTide,
                      onShowCwaTideChanged: (v) => setState(() => _showCwaTide = v),
                      showCwaBuoy: _showCwaBuoy,
                      onShowCwaBuoyChanged: (v) => setState(() => _showCwaBuoy = v),
                      showOceanCurrent: _showOceanCurrent,
                      onShowOceanCurrentChanged: (v) {
                        if (kIsWeb) {
                          WebActionDebugLog.instance.append(
                            "[ocean] toggle showOceanCurrent=$v",
                          );
                        }
                        setState(() => _showOceanCurrent = v);
                        if (v && kIsWeb) {
                          unawaited(_refreshOceanFlowField());
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 手機／非 Web：`flutter_map` 可與 Stack 疊加，維持左上角浮層。
  Widget _buildNonWebBody(double safeLeft) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        _fishingMapFill(),
        if (_filterPanelExpanded)
          Positioned.fill(
            child: PointerInterceptor(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _filterExpansionController?.collapse(),
              ),
            ),
          ),
        Positioned(
          top: 8,
          left: 8 + safeLeft,
          child: PointerInterceptor(
            child: SpotCategoryFilterPanel(
              expansionController: _filterExpansionController!,
              onExpansionChanged: (expanded) {
                setState(() => _filterPanelExpanded = expanded);
                if (expanded) {
                  pushMapboxInteractionBlock();
                } else {
                  popMapboxInteractionBlock();
                }
              },
              visibleIds: _visibleCategoryIds,
              onVisibleIdsChanged: (next) =>
                  setState(() => _visibleCategoryIds = next),
              showCwaTide: _showCwaTide,
              onShowCwaTideChanged: (v) =>
                  setState(() => _showCwaTide = v),
              showCwaBuoy: _showCwaBuoy,
              onShowCwaBuoyChanged: (v) =>
                  setState(() => _showCwaBuoy = v),
              showOceanCurrent: _showOceanCurrent,
              onShowOceanCurrentChanged: (v) {
                if (kIsWeb) {
                  WebActionDebugLog.instance.append(
                    "[ocean] toggle showOceanCurrent=$v",
                  );
                }
                setState(() => _showOceanCurrent = v);
                if (v && kIsWeb) {
                  unawaited(_refreshOceanFlowField());
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeLeft = MediaQuery.paddingOf(context).left;
    return Scaffold(
      appBar: AppBar(
        title: const Text("釣魚地圖"),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: widget.auth.guestModeListenable,
            builder: (context, isGuest, _) {
              if (isGuest) return const SizedBox.shrink();
              return StreamBuilder<bool>(
                stream: widget.auth.adminChanges,
                builder: (context, snapshot) {
                  if (snapshot.data != true) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Chip(
                      avatar: const Icon(Icons.verified_user_rounded, size: 16),
                      label: const Text("管理員"),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                },
              );
            },
          ),
          PopupMenuButton<void>(
            tooltip: "帳戶設定",
            icon: const Icon(Icons.tune_rounded),
            offset: const Offset(0, 42),
            elevation: 0,
            color: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            itemBuilder: (context) => [
              PopupMenuItem<void>(
                enabled: false,
                padding: const EdgeInsets.all(0),
                child: PointerInterceptor(
                  child: MapSettingsPanel(
                    settingsListenable: widget.settingsListenable,
                  ),
                ),
              ),
            ],
          ),
          ValueListenableBuilder<bool>(
            valueListenable: widget.auth.guestModeListenable,
            builder: (context, isGuestMode, _) {
              if (isGuestMode) {
                return PopupMenuButton<void>(
                  tooltip: "登入",
                  icon: const Icon(Icons.login_rounded),
                  offset: const Offset(0, 42),
                  elevation: 0,
                  color: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  ),
                    itemBuilder: (context) => [
                      PopupMenuItem<void>(
                        enabled: false,
                        padding: const EdgeInsets.all(0),
                        child: PointerInterceptor(
                          child: AuthPopupPanel(auth: widget.auth),
                        ),
                      ),
                    ],
                  );
                }
                return StreamBuilder<User?>(
                stream: widget.auth.authChanges,
                builder: (context, snapshot) {
                  final isLoggedIn = snapshot.data != null;
                  if (isLoggedIn) {
                    return TextButton.icon(
                      onPressed: widget.auth.signOut,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text("登出"),
                    );
                  }
                  return PopupMenuButton<void>(
                    tooltip: "登入",
                    icon: const Icon(Icons.login_rounded),
                    offset: const Offset(0, 42),
                    elevation: 0,
                    color: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                    ),
                    itemBuilder: (context) => [
                      PopupMenuItem<void>(
                        enabled: false,
                        padding: const EdgeInsets.all(0),
                        child: PointerInterceptor(
                          child: AuthPopupPanel(auth: widget.auth),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: kIsWeb
          ? StreamBuilder<bool>(
              stream: widget.auth.adminChanges,
              builder: (context, adminSnap) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildWebBody(context, safeLeft),
                    if (adminSnap.data == true) const AdminWebActionDebugPanel(),
                  ],
                );
              },
            )
          : _buildNonWebBody(safeLeft),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _togglePickMode(context),
        icon: Icon(_pickMode ? Icons.close_rounded : Icons.add_location_alt_outlined),
        label: Text(_pickMode ? "取消選點" : "新增釣點"),
      ),
    );
  }
}
