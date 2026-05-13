import "package:fishing_map/models/map_view_settings.dart";
import "package:fishing_map/models/user_firestore_summary.dart";
import "package:fishing_map/models/user_profile_extra.dart";
import "package:fishing_map/services/user_settings_repository.dart";
import "package:flutter/material.dart";

/// 管理員：Firestore `users` 文件（地圖設定／簡介）。
class AdminFirestoreUsersTab extends StatelessWidget {
  const AdminFirestoreUsersTab({super.key, required this.settingsRepo});

  final UserSettingsRepository settingsRepo;

  String _fmt(DateTime? d) {
    if (d == null) return "—";
    final x = d.toLocal();
    return "${x.year}/${x.month}/${x.day} ${x.hour.toString().padLeft(2, "0")}:"
        "${x.minute.toString().padLeft(2, "0")}";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            "僅列出已有 Firestore「users」文件的 uid；可改地圖語言／樣式與個人簡介。",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<UserFirestoreSummary>>(
            stream: settingsRepo.watchAllUserSummaries(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      "讀取失敗：${snap.error}",
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snap.data!;
              if (rows.isEmpty) {
                return const Center(child: Text("尚無任何 users 文件"));
              }
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final bio = r.extra.bio.trim();
                  return ListTile(
                    title: Text(
                      r.uid,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: "monospace",
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      "${r.mapSettings.language.label} · ${r.mapSettings.style.label}"
                      "${bio.isEmpty ? "" : "\n$bio"}",
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      _fmt(r.updatedAt ?? r.profileUpdatedAt),
                      style: theme.textTheme.labelSmall,
                    ),
                    onTap: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (ctx) => AdminFirestoreUserEditScreen(
                            settingsRepo: settingsRepo,
                            summary: r,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class AdminFirestoreUserEditScreen extends StatefulWidget {
  const AdminFirestoreUserEditScreen({
    super.key,
    required this.settingsRepo,
    required this.summary,
  });

  final UserSettingsRepository settingsRepo;
  final UserFirestoreSummary summary;

  @override
  State<AdminFirestoreUserEditScreen> createState() =>
      _AdminFirestoreUserEditScreenState();
}

class _AdminFirestoreUserEditScreenState extends State<AdminFirestoreUserEditScreen> {
  late MapLabelLanguage _lang;
  late MapVisualStyle _style;
  late final TextEditingController _bio;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _lang = widget.summary.mapSettings.language;
    _style = widget.summary.mapSettings.style;
    _bio = TextEditingController(text: widget.summary.extra.bio);
  }

  @override
  void dispose() {
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.settingsRepo.saveMapSettings(
        widget.summary.uid,
        MapViewSettings(language: _lang, style: _style),
      );
      await widget.settingsRepo.saveProfileExtra(
        widget.summary.uid,
        UserProfileExtra(bio: _bio.text),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("已儲存")),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("編輯 Firestore 使用者")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SelectableText(
            widget.summary.uid,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: "monospace"),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: "地圖語言",
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<MapLabelLanguage>(
                isExpanded: true,
                value: _lang,
                items: [
                  for (final l in MapLabelLanguage.values)
                    DropdownMenuItem(value: l, child: Text(l.label)),
                ],
                onChanged: _busy
                    ? null
                    : (v) {
                        if (v != null) setState(() => _lang = v);
                      },
              ),
            ),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: "地圖樣式",
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<MapVisualStyle>(
                isExpanded: true,
                value: _style,
                items: [
                  for (final s in MapVisualStyle.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: _busy
                    ? null
                    : (v) {
                        if (v != null) setState(() => _style = v);
                      },
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bio,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: "個人簡介（profileBio）",
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text("儲存"),
          ),
        ],
      ),
    );
  }
}
