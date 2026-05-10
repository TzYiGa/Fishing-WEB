import "package:flutter/material.dart";

/// 釣點類型：海水／淡水與子類，ID 與 Mapbox GeoJSON `category` 屬性一致。
class SpotCategoryOption {
  const SpotCategoryOption({
    required this.id,
    required this.groupLabel,
    required this.sublabel,
  });

  /// `1-1` … `2-3`
  final String id;
  final String groupLabel;
  final String sublabel;

  String get fullLabel => "$groupLabel · $sublabel";
}

/// 固定順序列表（表單與圖例用）。
const List<SpotCategoryOption> kSpotCategoryOptions = [
  SpotCategoryOption(id: "1-1", groupLabel: "海水", sublabel: "鐵板"),
  SpotCategoryOption(id: "1-2", groupLabel: "海水", sublabel: "磯釣"),
  SpotCategoryOption(id: "1-3", groupLabel: "海水", sublabel: "岸拋"),
  SpotCategoryOption(id: "1-4", groupLabel: "海水", sublabel: "前打"),
  SpotCategoryOption(id: "2-1", groupLabel: "淡水", sublabel: "路亞"),
  SpotCategoryOption(id: "2-2", groupLabel: "淡水", sublabel: "池釣"),
  SpotCategoryOption(id: "2-3", groupLabel: "淡水", sublabel: "溪流"),
];

/// 舊資料或非法值時使用（海水 · 磯釣）。
const String kDefaultSpotCategoryId = "1-2";

SpotCategoryOption? spotCategoryById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final o in kSpotCategoryOptions) {
    if (o.id == id) return o;
  }
  return null;
}

String spotCategoryLabelResolved(String? id) {
  final o = spotCategoryById(id);
  if (o != null) return o.fullLabel;
  return "未分類";
}

/// 與 `mapbox_gl_bridge.js` 單點顏色一致，供 FlutterMap 等非 Web 端標記用。
Color spotCategoryMapMarkerColor(String categoryId) {
  return switch (categoryId) {
    "1-1" => const Color(0xFF075985),
    "1-2" => const Color(0xFF0284C7),
    "1-3" => const Color(0xFF0D9488),
    "1-4" => const Color(0xFF0369A1),
    "2-1" => const Color(0xFF15803D),
    "2-2" => const Color(0xFF16A34A),
    "2-3" => const Color(0xFF22C55E),
    _ => const Color(0xFF94A3B8),
  };
}
