import "package:fishing_map/models/spot_category.dart";
import "package:fishing_map/widgets/cwa_map_marker_assets.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";

/// 左上角白名單：勾選要顯示的釣點類型（[kSpotCategoryOptions] 的 id），
/// 以及是否顯示中央氣象署測站圖層。
class SpotCategoryFilterPanel extends StatelessWidget {
  const SpotCategoryFilterPanel({
    super.key,
    this.expansionController,
    this.onExpansionChanged,
    required this.visibleIds,
    required this.onVisibleIdsChanged,
    required this.showCwaTide,
    required this.onShowCwaTideChanged,
    required this.showCwaBuoy,
    required this.onShowCwaBuoyChanged,
    required this.showOceanCurrent,
    required this.onShowOceanCurrentChanged,
  });

  /// 非 Web 疊在全螢幕地圖上時可選，用來收合並同步 Js 阻隔；Web 若浮層疊在地圖上請外層加 PointerInterceptor。
  final ExpansibleController? expansionController;
  final ValueChanged<bool>? onExpansionChanged;
  final Set<String> visibleIds;
  final ValueChanged<Set<String>> onVisibleIdsChanged;
  final bool showCwaTide;
  final ValueChanged<bool> onShowCwaTideChanged;
  final bool showCwaBuoy;
  final ValueChanged<bool> onShowCwaBuoyChanged;
  final bool showOceanCurrent;
  final ValueChanged<bool> onShowOceanCurrentChanged;

  void _set(Set<String> next) {
    onVisibleIdsChanged(Set<String>.from(next));
  }

  void _toggle(String id, bool? checked) {
    final next = {...visibleIds};
    if (checked == true) {
      next.add(id);
    } else {
      next.remove(id);
    }
    _set(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget row(SpotCategoryOption o) {
      return CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: visibleIds.contains(o.id),
        onChanged: (v) => _toggle(o.id, v),
        title: Text(o.sublabel, style: theme.textTheme.bodyMedium),
        secondary: Icon(Icons.circle, size: 12, color: spotCategoryMapMarkerColor(o.id)),
      );
    }

    return Material(
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.92),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 268),
        child: Theme(
          data: theme.copyWith(
            checkboxTheme: const CheckboxThemeData(
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          child: ExpansionTile(
            controller: expansionController,
            onExpansionChanged: onExpansionChanged,
            initiallyExpanded: false,
            tilePadding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            leading: Icon(Icons.filter_alt_outlined, size: 20, color: cs.primary),
            title: Text("顯示類型", style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text(
              "${visibleIds.length}/${kSpotCategoryOptions.length} 類",
              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            children: [
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: showCwaTide,
                onChanged: (v) => onShowCwaTideChanged(v ?? false),
                title: Text(
                  "潮位站",
                  style: theme.textTheme.bodyMedium,
                ),
                secondary: SvgPicture.asset(
                  CwaMapMarkerAssets.tideSvg,
                  width: 28,
                  height: 28,
                  fit: BoxFit.contain,
                ),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: showCwaBuoy,
                onChanged: (v) => onShowCwaBuoyChanged(v ?? false),
                title: Text(
                  "浮標站／浮球站",
                  style: theme.textTheme.bodyMedium,
                ),
                secondary: SvgPicture.asset(
                  CwaMapMarkerAssets.buoySvg,
                  width: 28,
                  height: 28,
                  fit: BoxFit.contain,
                ),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: showOceanCurrent,
                onChanged: (v) => onShowOceanCurrentChanged(v ?? false),
                title: Text(
                  "海流（Copernicus）",
                  style: theme.textTheme.bodyMedium,
                ),
                secondary: Icon(
                  Icons.stream_rounded,
                  size: 26,
                  color: cs.primary,
                ),
              ),
              const Divider(height: 1),
              Row(
                children: [
                  TextButton(
                    onPressed: () => _set({for (final o in kSpotCategoryOptions) o.id}),
                    child: const Text("全選"),
                  ),
                  TextButton(
                    onPressed: () => _set({}),
                    child: const Text("全不選"),
                  ),
                ],
              ),
              const Divider(height: 1),
              Text("海水", style: theme.textTheme.labelLarge?.copyWith(color: cs.primary)),
              ...kSpotCategoryOptions.where((o) => o.id.startsWith("1-")).map(row),
              const SizedBox(height: 4),
              Text("淡水", style: theme.textTheme.labelLarge?.copyWith(color: cs.tertiary)),
              ...kSpotCategoryOptions.where((o) => o.id.startsWith("2-")).map(row),
            ],
          ),
        ),
      ),
    );
  }
}
