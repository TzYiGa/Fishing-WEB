import "package:fishing_map/services/web_action_debug_log.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:pointer_interceptor/pointer_interceptor.dart";

/// 僅管理員可見：浮動記錄 Mapbox bridge／Flutter Web 與相關動作。
class AdminWebActionDebugPanel extends StatefulWidget {
  const AdminWebActionDebugPanel({super.key});

  @override
  State<AdminWebActionDebugPanel> createState() =>
      _AdminWebActionDebugPanelState();
}

class _AdminWebActionDebugPanelState extends State<AdminWebActionDebugPanel> {
  final _log = WebActionDebugLog.instance;
  final _scroll = ScrollController();
  bool _expanded = true;
  bool _pauseScroll = false;

  @override
  void initState() {
    super.initState();
    // JS  sink 已由 [MapHomeScreen.initState] 提早安裝，此處僅訂閱更新 UI。
    _log.addListener(_onLog);
  }

  void _onLog() {
    if (!mounted) return;
    setState(() {});
    if (!_pauseScroll && _scroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _log.removeListener(_onLog);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _copyAll() async {
    final text = _log.lines.join("\n");
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("已複製全部記錄到剪貼簿")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final h = _expanded ? (media.size.height * 0.34).clamp(160.0, 420.0) : 44.0;

    return Positioned(
      left: 8,
      right: 8,
      // 避開 FAB.extended（約 56–72）以免擋按鈕。
      bottom: 80 + media.padding.bottom,
      height: h,
      child: PointerInterceptor(
        child: Material(
          elevation: 8,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.35),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: Theme.of(context).colorScheme.errorContainer.withValues(
                      alpha: 0.35,
                    ),
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.bug_report_rounded,
                          size: 20,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "DEBUG 網頁動作（管理員） · ${_log.lines.length} 行",
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        Icon(
                          _expanded ? Icons.expand_more : Icons.expand_less,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_expanded) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => _log.clear(),
                        child: const Text("清除"),
                      ),
                      TextButton(
                        onPressed: _copyAll,
                        child: const Text("複製全部"),
                      ),
                      const Spacer(),
                      FilterChip(
                        label: const Text("暫停捲動"),
                        selected: _pauseScroll,
                        onSelected: (v) => setState(() => _pauseScroll = v),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Scrollbar(
                    controller: _scroll,
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                      itemCount: _log.lines.length,
                      itemBuilder: (context, i) {
                        return SelectableText(
                          _log.lines[i],
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontFamily: "monospace",
                                fontSize: 11,
                                height: 1.25,
                              ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
