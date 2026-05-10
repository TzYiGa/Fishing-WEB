/// 編譯時傳入：flutter run -d chrome --dart-define=MAPBOX_ACCESS_TOKEN=pk.xxx
const String mapboxAccessToken = String.fromEnvironment(
  "MAPBOX_ACCESS_TOKEN",
  defaultValue: "",
);

/// Optional: language-specific custom style ids from Mapbox Studio.
///
/// Example:
/// flutter run -d chrome --dart-define=MAPBOX_STYLE_ZH_HANT=youruser/yourstyleid
const String mapboxStyleZhHant = String.fromEnvironment(
  "MAPBOX_STYLE_ZH_HANT",
  defaultValue: "",
);

const String mapboxStyleZhHans = String.fromEnvironment(
  "MAPBOX_STYLE_ZH_HANS",
  defaultValue: "",
);

const String mapboxStyleEn = String.fromEnvironment(
  "MAPBOX_STYLE_EN",
  defaultValue: "",
);

/// 中央氣象署開放資料平臺 Authorization（格式通常為 `CWA-...`）。
/// 編譯時：`flutter run ... --dart-define=CWA_AUTHORIZATION=CWA-你的授權碼`
/// 請勿把真實密鑰寫進程式碼或註解（會被 Git 記錄）。
/// 未設定時，無法向氣象署 opendata 擷取 O-B0075-002／001（畫面將顯示缺漏說明）。
const String cwaAuthorization = String.fromEnvironment(
  "CWA_AUTHORIZATION",
  defaultValue: "",
);
