import "package:flutter/material.dart";

enum MapLabelLanguage {
  traditionalChinese,
  simplifiedChinese,
  english,
}

extension MapLabelLanguageMaterialLocale on MapLabelLanguage {
  /// Material 日期／時間選擇器與同語系 UI 用。
  Locale get materialLocale {
    switch (this) {
      case MapLabelLanguage.traditionalChinese:
        return const Locale("zh", "TW");
      case MapLabelLanguage.simplifiedChinese:
        return const Locale("zh", "CN");
      case MapLabelLanguage.english:
        return const Locale("en");
    }
  }
}

extension MapLabelLanguageX on MapLabelLanguage {
  String get label {
    switch (this) {
      case MapLabelLanguage.traditionalChinese:
        return "繁體中文";
      case MapLabelLanguage.simplifiedChinese:
        return "简体中文";
      case MapLabelLanguage.english:
        return "English";
    }
  }

  String get mapboxNameField {
    switch (this) {
      case MapLabelLanguage.traditionalChinese:
        return "name_zh-Hant";
      case MapLabelLanguage.simplifiedChinese:
        return "name_zh-Hans";
      case MapLabelLanguage.english:
        return "name_en";
    }
  }
}

enum MapVisualStyle {
  outdoors,
  streets,
  satellite,
  light,
  dark,
}

extension MapVisualStyleX on MapVisualStyle {
  String get label {
    switch (this) {
      case MapVisualStyle.outdoors:
        return "戶外";
      case MapVisualStyle.streets:
        return "街道";
      case MapVisualStyle.satellite:
        return "衛星";
      case MapVisualStyle.light:
        return "淺色";
      case MapVisualStyle.dark:
        return "深色";
    }
  }

  String get mapboxStyleId {
    switch (this) {
      case MapVisualStyle.outdoors:
        return "outdoors-v12";
      case MapVisualStyle.streets:
        return "streets-v12";
      case MapVisualStyle.satellite:
        return "satellite-streets-v12";
      case MapVisualStyle.light:
        return "light-v11";
      case MapVisualStyle.dark:
        return "dark-v11";
    }
  }
}

class MapViewSettings {
  const MapViewSettings({
    this.language = MapLabelLanguage.traditionalChinese,
    this.style = MapVisualStyle.outdoors,
  });

  final MapLabelLanguage language;
  final MapVisualStyle style;

  MapViewSettings copyWith({
    MapLabelLanguage? language,
    MapVisualStyle? style,
  }) {
    return MapViewSettings(
      language: language ?? this.language,
      style: style ?? this.style,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "language": language.name,
      "style": style.name,
      "updatedAt": DateTime.now().toUtc(),
    };
  }

  static MapViewSettings fromMap(Map<String, dynamic>? data) {
    if (data == null) return const MapViewSettings();
    return MapViewSettings(
      language: _parseLanguage(data["language"] as String?),
      style: _parseStyle(data["style"] as String?),
    );
  }

  static MapLabelLanguage _parseLanguage(String? value) {
    for (final candidate in MapLabelLanguage.values) {
      if (candidate.name == value) return candidate;
    }
    return MapLabelLanguage.traditionalChinese;
  }

  static MapVisualStyle _parseStyle(String? value) {
    for (final candidate in MapVisualStyle.values) {
      if (candidate.name == value) return candidate;
    }
    return MapVisualStyle.outdoors;
  }
}
