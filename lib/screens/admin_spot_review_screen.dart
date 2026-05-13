import "package:fishing_map/models/fishing_spot.dart";
import "package:fishing_map/models/spot_category.dart";
import "package:fishing_map/models/spot_moderation_status.dart";
import "package:fishing_map/services/spot_repository.dart";
import "package:flutter/material.dart";

/// 管理員：審核待發布「固定釣點」。
class AdminSpotReviewScreen extends StatelessWidget {
  const AdminSpotReviewScreen({
    super.key,
    required this.repo,
  });

  final SpotRepository repo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("固定釣點審核")),
      body: StreamBuilder<List<FishingSpot>>(
        stream: repo.watchPendingSpots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snap.error.toString(),
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
            return const Center(child: Text("目前沒有待審核的固定釣點"));
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = rows[i];
              return ListTile(
                title: Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  "${spotCategoriesSummaryLabel(s.categoryIds)} · ${s.description.isEmpty ? "（無描述）" : s.description}",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => _reject(context, s),
                      child: const Text("拒絕"),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: () => _approve(context, s),
                      child: const Text("核准"),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _approve(BuildContext context, FishingSpot s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("核准固定釣點"),
        content: Text("確定將「${s.name}」顯示於公開地圖？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("取消"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("核准"),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await repo.setModerationStatus(
        spotId: s.id,
        status: SpotModerationStatus.approved,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("已核准：${s.name}")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _reject(BuildContext context, FishingSpot s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("拒絕固定釣點"),
        content: const Text(
          "拒絕後該標點不會顯示於地圖；作者仍可在 Firebase 中看到自己的項目。",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("取消"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("拒絕"),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await repo.setModerationStatus(
        spotId: s.id,
        status: SpotModerationStatus.rejected,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("已拒絕：${s.name}")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }
}
