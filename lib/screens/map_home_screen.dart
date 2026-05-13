import "dart:async";

import "package:fishing_map/app_version.dart";
import "package:fishing_map/data/cwa_station_loader.dart";
import "package:fishing_map/services/copernicus_ocean_vector_service.dart";
import "package:fishing_map/models/cwa_station_point.dart";
import "package:fishing_map/models/spot_entry_kind.dart";
import "package:fishing_map/models/fishing_spot.dart";
import "package:fishing_map/models/spot_category.dart";
import "package:fishing_map/models/map_view_settings.dart";
import "package:fishing_map/screens/admin_spot_review_screen.dart";
import "package:fishing_map/screens/admin_users_screen.dart";
import "package:fishing_map/services/admin_auth_api.dart";
import "package:fishing_map/screens/auth_popup_panel.dart";
import "package:fishing_map/screens/map_settings_screen.dart";
import "package:fishing_map/screens/member_screen.dart";
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
import "package:fishing_map/widgets/spot_search_bar.dart";
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
  late final AdminAuthApi _adminAuthApi = AdminAuthApi();
  /// 非 null 時：地圖點選會建立該類型（釣況分享／固定釣點）。
  SpotEntryKind? _pickKind;
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
  static const Duration _oceanAutoRefreshInterval = Duration(minutes: 30);
  Timer? _oceanAutoRefresh;
  ExpansibleController? _filterExpansionController;
  bool _filterPanelExpanded = false;
  final TextEditingController _spotSearchCtrl = TextEditingController();
  /// 白名單：僅顯示勾選之類型對應的釣點。
  Set<String> _visibleCategoryIds = {for (final o in kSpotCategoryOptions) o.id};
  bool _addMenuOpen = false;
  String? _activeUid;
  bool _applyingRemoteSettings = false;

  List<FishingSpot> get _visibleSpots {
    final q = _spotSearchCtrl.text.trim().toLowerCase();
    return _spots.where((s) {
      if (!s.showsOnPublicMap) return false;
      if (!s.matchesCategoryFilter(_visibleCategoryIds)) return false;
      if (q.isEmpty) return true;
      return s.name.toLowerCase().contains(q) ||
          s.description.toLowerCase().contains(q);
    }).toList();
  }

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

  void _syncOceanAutoRefreshTimer() {
    _oceanAutoRefresh?.cancel();
    _oceanAutoRefresh = null;
    if (!_showOceanCurrent || !kIsWeb) return;
    _oceanAutoRefresh = Timer.periodic(_oceanAutoRefreshInterval, (_) {
      if (!mounted || !_showOceanCurrent || !kIsWeb) return;
      unawaited(_refreshOceanFlowField());
    });
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
    _spotSearchCtrl.dispose();
    _oceanAutoRefresh?.cancel();
    _authSub?.cancel();
    _spotsSub?.cancel();
    widget.settingsListenable.removeListener(_persistSettingsForUser);
    widget.auth.guestModeListenable.removeListener(_onGuestModeChanged);
    if (kIsWeb) {
      uninstallWebAdminDebugSink();
    }
    super.dispose();
  }

  Future<void> _beginPickKind(BuildContext ctx, SpotEntryKind kind) async {
    if (widget.auth.currentUser == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text("請先登入")),
      );
      return;
    }
    setState(() {
      _pickKind = kind;
      _addMenuOpen = false;
    });
    if (!ctx.mounted) return;
    final hint = kind == SpotEntryKind.conditionShare
        ? "在地圖上點選要分享的位置"
        : "在地圖上點選固定釣點位置";
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(hint),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _cancelPick() {
    setState(() {
      _pickKind = null;
      _addMenuOpen = false;
    });
  }

  Widget _buildQuickAddFab(BuildContext context) {
    if (_pickKind != null) {
      return FloatingActionButton.extended(
        heroTag: "fab_cancel_pick",
        onPressed: _cancelPick,
        icon: const Icon(Icons.close_rounded),
        label: const Text("取消選點"),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                axisAlignment: 1,
                child: child,
              ),
            );
          },
          child: _addMenuOpen
              ? Column(
                  key: const ValueKey("fab_add_open"),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FloatingActionButton.extended(
                      heroTag: "fab_condition_share",
                      onPressed: () =>
                          _beginPickKind(context, SpotEntryKind.conditionShare),
                      icon: const Icon(Icons.photo_camera_rounded),
                      label: const Text("釣況分享"),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.extended(
                      heroTag: "fab_fishing_poi",
                      onPressed: () =>
                          _beginPickKind(context, SpotEntryKind.fishingPoi),
                      icon: const Icon(Icons.flag_circle_rounded),
                      label: const Text("新增固定釣點"),
                    ),
                    const SizedBox(height: 10),
                  ],
                )
              : const SizedBox.shrink(key: ValueKey("fab_add_closed")),
        ),
        FloatingActionButton(
          heroTag: "fab_add_toggle",
          onPressed: () => setState(() => _addMenuOpen = !_addMenuOpen),
          child: AnimatedRotation(
            duration: const Duration(milliseconds: 220),
            turns: _addMenuOpen ? 0.125 : 0,
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ],
    );
  }

  Future<void> _onMapPick(LatLng latlng, BuildContext ctx) async {
    final kind = _pickKind;
    if (kind == null) return;
    setState(() => _pickKind = null);
    if (!mounted) return;
    final outcome = await AddSpotSheet.open(
      ctx,
      pick: latlng,
      repo: widget.repo,
      auth: widget.auth,
      mapLanguage: widget.settingsListenable.value.language,
      entryKind: kind,
    );
    if (!mounted || outcome == null) return;
    final msg = switch (outcome) {
      AddSpotSheetOutcome.conditionSharePublished => "已發布釣況分享",
      AddSpotSheetOutcome.fishingPoiSubmittedPending =>
        "固定釣點已提交審核，核准後會顯示於地圖",
      AddSpotSheetOutcome.fishingPoiPublishedApproved =>
        "固定釣點已建立並顯示於地圖",
    };
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

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
      pickMode: _pickKind != null,
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
      onSpotTap: (s) => SpotDetailSheet.open(
          context,
          spot: s,
          repo: widget.repo,
          auth: widget.auth,
          mapLanguage: widget.settingsListenable.value.language,
        ),
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
        final narrow = constraints.maxWidth < 420;
        final searchTop = narrow ? 120.0 : 8.0;
        final searchLeft = narrow ? (safeLeft + 8) : (safeLeft + 288);
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
                        _syncOceanAutoRefreshTimer();
                      },
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: searchLeft,
              right: 8,
              top: searchTop,
              child: PointerInterceptor(
                child: SpotSearchBar(
                  controller: _spotSearchCtrl,
                  onChanged: (_) => setState(() {}),
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
                _syncOceanAutoRefreshTimer();
              },
            ),
          ),
        ),
        Positioned(
          top: 8,
          left: 8 + safeLeft + 288,
          right: 8,
          child: PointerInterceptor(
            child: SpotSearchBar(
              controller: _spotSearchCtrl,
              onChanged: (_) => setState(() {}),
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
                  final scheme = Theme.of(context).colorScheme;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: PopupMenuButton<String>(
                      tooltip: "管理員",
                      offset: const Offset(0, 44),
                      onSelected: (value) {
                        if (!context.mounted) return;
                        if (value == "users") {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (ctx) => AdminUsersScreen(
                                settingsRepo: _settingsRepo,
                                adminAuthApi: _adminAuthApi,
                              ),
                            ),
                          );
                        } else if (value == "spot_review") {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (ctx) => AdminSpotReviewScreen(
                                repo: widget.repo,
                              ),
                            ),
                          );
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem<String>(
                          value: "users",
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: Icon(Icons.people_outline_rounded),
                            title: Text("使用者資料"),
                            subtitle: Text(
                              "Auth（Admin SDK）與 Firestore 使用者資料",
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: "spot_review",
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: Icon(Icons.fact_check_outlined),
                            title: Text("固定釣點審核"),
                            subtitle: Text(
                              "核准或拒絕會員提交的固定釣點",
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified_user_rounded,
                              size: 18,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "管理員",
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            Icon(
                              Icons.arrow_drop_down_rounded,
                              size: 22,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
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
          StreamBuilder<User?>(
            stream: widget.auth.authChanges,
            builder: (context, snapshot) {
              if (snapshot.data == null) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: "會員",
                icon: const Icon(Icons.person_outline_rounded),
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (ctx) => MemberScreen(auth: widget.auth),
                    ),
                  );
                },
              );
            },
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          kIsWeb
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
          IgnorePointer(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                // 右下留出空間給 Mapbox logo／attribution（Flutter 疊在圖上時易重疊）。
                padding: const EdgeInsets.only(right: 156, bottom: 14),
                child: Opacity(
                  opacity: 0.35,
                  child: Text(
                    "v$kAppVersion",
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildQuickAddFab(context),
    );
  }
}
