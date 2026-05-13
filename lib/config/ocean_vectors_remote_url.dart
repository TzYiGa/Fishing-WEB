/// Copernicus 海流向量 JSON 的公開讀取 URL（由 CI 上傳至 Firebase Storage `ocean/`）。
///
/// 與 `--dart-define=OCEAN_VECTORS_JSON_URL=...` 並用時：**dart-define 優先**；兩者皆空則讀
/// [CopernicusOceanVectorService] 內建 asset。
///
/// 部署 Storage 規則後，此 URL 應可被匿名 GET（見專案根目錄 `storage.rules`）。
const String kOceanVectorsRemoteJsonUrl =
    "https://firebasestorage.googleapis.com/v0/b/fishing-web-ab5ad.firebasestorage.app/o/ocean%2Fcopernicus_ocean_vectors.json?alt=media";
