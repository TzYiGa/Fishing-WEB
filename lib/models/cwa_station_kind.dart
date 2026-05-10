/// 與 [StationID.json] 之 `StationAttribute`／`StationAttributeEN` 對應之地圖分類。
///
/// [other]：例「氣象站」等，不依此二分顯示於海象層（仍參與最近站比對时可擴充）。
enum CwaStationKind {
  /// 潮位站（`Tidal`）
  tide,

  /// 浮標站、浮球式波浪站等（`Buoy`）
  buoy,

  /// 其餘（海岸氣象站等），預設不畫在此二類圖層上。
  other,
}
