import "dart:async";
import "dart:convert";

import "package:cached_network_image/cached_network_image.dart";
import "package:fishing_map/models/fishing_spot.dart";
import "package:fishing_map/models/spot_category.dart";
import "package:fishing_map/models/spot_comment.dart";
import "package:fishing_map/services/auth_service.dart";
import "package:fishing_map/services/spot_repository.dart";
import "package:fishing_map/widgets/mapbox_interaction_overlay.dart";
import "package:fishing_map/widgets/spot_environment_card.dart";
import "package:fishing_map/utils/relative_time_zh.dart";
import "package:flutter/material.dart";

class SpotDetailSheet extends StatefulWidget {
  const SpotDetailSheet({
    super.key,
    required this.spot,
    required this.repo,
    required this.auth,
  });

  final FishingSpot spot;
  final SpotRepository repo;
  final AuthService auth;

  static void open(
    BuildContext context, {
    required FishingSpot spot,
    required SpotRepository repo,
    required AuthService auth,
  }) {
    final size = MediaQuery.sizeOf(context);
    final screenW = size.width;
    // 約螢幕寬的 2/3，略留邊際；Center + SizedBox + constraints 並用以確保 Web 上也置中且不滿屏。
    final sheetW = (screenW * 2 / 3).clamp(260.0, screenW - 8);
    final sheetMaxH = size.height * 0.52;
    pushMapboxInteractionBlock();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      // 許多版型下只靠 ConstrainedBox 無效——須同時約束 Modal 本身的 maxWidth / 並給 child 固定寬度。
      constraints: BoxConstraints(
        maxHeight: sheetMaxH,
        maxWidth: sheetW,
      ),
      // isScrollControlled 下若不給子樹「有限高度」，Column + Expanded（留言區／輸入框）版面會壞，
      // 表現為點不到留言／鍵盤區。
      builder: (ctx) => LayoutBuilder(
        builder: (_, c) {
          final finiteH =
              c.maxHeight.isFinite && c.maxHeight > 0 ? c.maxHeight : sheetMaxH;
          return Center(
            child: SizedBox(
              width: sheetW,
              height: finiteH,
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(ctx).bottom),
                child: SpotDetailSheet(spot: spot, repo: repo, auth: auth),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() => popMapboxInteractionBlock());
  }

  @override
  State<SpotDetailSheet> createState() => _SpotDetailSheetState();
}

class _SpotDetailSheetState extends State<SpotDetailSheet> {
  final _text = TextEditingController();
  bool _sending = false;
  String? _error;
  Timer? _relativeTimeTicker;
  bool? _bootstrapAdmin;

  @override
  void initState() {
    super.initState();
    _relativeTimeTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    widget.auth.isCurrentUserAdmin().then((v) {
      if (mounted) setState(() => _bootstrapAdmin = v);
    });
  }

  @override
  void dispose() {
    _relativeTimeTicker?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final u = widget.auth.currentUser;
    if (u == null) {
      setState(() => _error = "請登入後留言");
      return;
    }
    final trim = _text.text.trim();
    if (trim.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.repo.addComment(
        spotId: widget.spot.id,
        comment: SpotComment(
          id: "",
          text: trim,
          userId: u.uid,
          authorLabel: widget.auth.labelFor(u),
          createdAt: DateTime.now(),
        ),
        userId: u.uid,
        authorLabel: widget.auth.labelFor(u),
      );
      _text.clear();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirmAndDelete(SpotComment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("刪除留言"),
        content: const Text("確定要刪除這則留言嗎？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("取消"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("刪除"),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final u = widget.auth.currentUser;
    if (u == null) return;
    try {
      final admin = await widget.auth.isCurrentUserAdmin();
      await widget.repo.deleteComment(
        spotId: widget.spot.id,
        commentId: c.id,
        requesterUserId: u.uid,
        requesterIsAdmin: admin,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final now = DateTime.now();

    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Column(
        children: [
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.spot.name,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(
                      label: Text(spotCategoryLabelResolved(widget.spot.categoryId)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SpotEnvironmentCard(spot: widget.spot),
                  const SizedBox(height: 12),
                  Text(
                    widget.spot.description.isEmpty ? "尚未填寫描述" : widget.spot.description,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  if (widget.spot.photoUrls.isNotEmpty) ...[
                    Text("照片", style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.spot.photoUrls.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) {
                          final url = widget.spot.photoUrls[i];
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AspectRatio(
                              aspectRatio: 4 / 3,
                              child: url.startsWith("data:image/")
                                  ? Image.memory(
                                      base64Decode(url.split(",").last),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Center(
                                        child: Icon(Icons.broken_image_outlined),
                                      ),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: url,
                                      fit: BoxFit.cover,
                                      progressIndicatorBuilder: (_, __, prog) =>
                                          const Center(child: CircularProgressIndicator()),
                                      errorWidget: (_, __, ___) =>
                                          const Center(child: Icon(Icons.broken_image_outlined)),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                  child: Text("留言", style: theme.textTheme.titleSmall),
                ),
                Expanded(
                  child: StreamBuilder<List<SpotComment>>(
                    stream: widget.repo.watchComments(widget.spot.id),
                    builder: (ctx, snap) {
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final cs = snap.data!;
                      if (cs.isEmpty) {
                        return Center(
                          child: Text(
                            "尚無留言，搶頭香！",
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      }
                      return StreamBuilder<bool>(
                        stream: widget.auth.adminChanges,
                        initialData: false,
                        builder: (ctx, adminSnap) {
                          final isAdmin =
                              adminSnap.data == true || _bootstrapAdmin == true;
                          final uid = widget.auth.currentUser?.uid;
                          return ListView.separated(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            itemCount: cs.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.35),
                            ),
                            itemBuilder: (_, i) {
                              final c = cs[i];
                              final canDelete = uid != null &&
                                  (uid == c.userId || isAdmin);
                              final timeLabel =
                                  formatCommentTimeZh(c.createdAt, now);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            c.text,
                                            style: theme.textTheme.bodyMedium,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            "${c.authorLabel} · $timeLabel",
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: theme.colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (canDelete)
                                      IconButton(
                                        tooltip: "刪除留言",
                                        icon: Icon(
                                          Icons.delete_outline_rounded,
                                          color: theme.colorScheme.error,
                                        ),
                                        onPressed: () => _confirmAndDelete(c),
                                      ),
                                  ],
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
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: SafeArea(
              top: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: "輸入留言⋯",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
        ],
      ),
    );
  }
}
