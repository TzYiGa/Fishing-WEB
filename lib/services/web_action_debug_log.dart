import "package:flutter/foundation.dart";

/// 全域 Web ／ Mapbox bridge 動作記錄（僅於 UI 對管理員顯示）。
class WebActionDebugLog extends ChangeNotifier {
  WebActionDebugLog._();

  /// 跨 widget／JS bridge 共用同一實例。
  static final WebActionDebugLog instance = WebActionDebugLog._();

  static const int maxLines = 450;

  final List<String> _lines = [];

  List<String> get lines => List.unmodifiable(_lines);

  void append(String message) {
    final ts =
        "${DateTime.now().toUtc().toIso8601String().substring(0, 23)}Z";
    _lines.add("[$ts] $message");
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }
}
