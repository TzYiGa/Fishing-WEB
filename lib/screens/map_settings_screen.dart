import "package:fishing_map/models/map_view_settings.dart";
import "package:flutter/material.dart";

class MapSettingsPanel extends StatelessWidget {
  const MapSettingsPanel({
    super.key,
    required this.settingsListenable,
  });

  final ValueNotifier<MapViewSettings> settingsListenable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 320,
      child: ValueListenableBuilder<MapViewSettings>(
        valueListenable: settingsListenable,
        builder: (context, settings, _) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 16,
                  offset: Offset(0, 8),
                  color: Color(0x26000000),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "地圖設定",
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SectionLabel(text: "地名語言"),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<MapLabelLanguage>(
                    isDense: true,
                    value: settings.language,
                    items: [
                      for (final language in MapLabelLanguage.values)
                        DropdownMenuItem(
                          value: language,
                          child: Text(language.label),
                        ),
                    ],
                    onChanged: (selected) {
                      if (selected == null) return;
                      settingsListenable.value = settings.copyWith(language: selected);
                    },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SectionLabel(text: "地圖顯示方式"),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<MapVisualStyle>(
                    isDense: true,
                    value: settings.style,
                    items: [
                      for (final style in MapVisualStyle.values)
                        DropdownMenuItem(
                          value: style,
                          child: Text(style.label),
                        ),
                    ],
                    onChanged: (selected) {
                      if (selected == null) return;
                      settingsListenable.value = settings.copyWith(style: selected);
                    },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }
}
