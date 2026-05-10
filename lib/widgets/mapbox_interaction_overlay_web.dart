import "dart:js_interop";

@JS("fishingMapSetInteractionsEnabledAll")
external void _jsSetInteractions(JSNumber enabledFlag);

int _mapInteractionBlockDepth = 0;

void _syncMapInteractionsToJs() {
  final allow = _mapInteractionBlockDepth <= 0;
  _jsSetInteractions((allow ? 1 : 0).toJS);
}

/// 與 [popMapboxInteractionBlock] 成對使用：疊加多處需阻擋地圖的 UI（篩選浮層、底表同時存在等）。
///
/// 每次增減深度後都會同步 JS：避免多餘的 [MouseRegion.onEnter] 疊加 push 後，
/// 僅一次 onExit 無法還原，導致地圖手勢與 Flutter 預期不一致、勾選無反應。
void pushMapboxInteractionBlock() {
  _mapInteractionBlockDepth++;
  _syncMapInteractionsToJs();
}

void popMapboxInteractionBlock() {
  if (_mapInteractionBlockDepth <= 0) return;
  _mapInteractionBlockDepth--;
  _syncMapInteractionsToJs();
}

/// 依目前 [pushMapboxInteractionBlock] 深度同步 JS 地圖手勢（例如地圖 Web 元件重建後）。
///
/// 不可將深度強制歸零：游標若仍留在篩選片 [MouseRegion] 內，Dart 不會再送 onEnter，
/// 歸零會讓地圖重新搶走指標，導致勾選／展開失效。
void setMapboxInteractionsEnabledGlobally(bool enabled) {
  if (enabled) {
    _syncMapInteractionsToJs();
  } else {
    pushMapboxInteractionBlock();
  }
}
