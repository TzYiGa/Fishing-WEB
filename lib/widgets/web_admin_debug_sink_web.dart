import "dart:js_interop";

import "package:fishing_map/services/web_action_debug_log.dart";

@JS("globalThis")
extension type _JSGlobal(JSObject _) implements JSObject {
  external set fishingMapDartDebug(JSFunction? f);
}

@JS("globalThis")
external _JSGlobal get _globalThisDebug;

/// 將 [WebActionDebugLog.instance] 接到 `globalThis.fishingMapDartDebug`（見 mapbox_gl_bridge.js `fmpDbg`）。
void installWebAdminDebugSink(void Function(String) onLine) {
  _globalThisDebug.fishingMapDartDebug = ((JSString msg) {
    onLine(msg.toDart);
  }).toJS;
}

void uninstallWebAdminDebugSink() {
  _globalThisDebug.fishingMapDartDebug = null;
}
