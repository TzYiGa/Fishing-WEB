import "package:fishing_map/screens/personal_profile_screen.dart";
import "package:fishing_map/services/auth_service.dart";
import "package:fishing_map/services/user_settings_repository.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

void _memberReferenceSnack(BuildContext context, String title) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text("$title · 版面參考，尚未接上實際功能"),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ),
  );
}

/// 登入後可開啟的會員／帳戶頁（功能可日後擴充）。
class MemberScreen extends StatefulWidget {
  const MemberScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<MemberScreen> createState() => _MemberScreenState();
}

class _MemberScreenState extends State<MemberScreen> {
  static const String _demoVersionLabel = "1.0.0+1"; // 與 pubspec 對齊，純展示用

  Future<void> _openPersonalProfile() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (ctx) => PersonalProfileScreen(
          auth: widget.auth,
          profileRepo: UserSettingsRepository(),
        ),
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<User?>(
      stream: widget.auth.authChanges,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) {
          return Scaffold(
            appBar: AppBar(title: const Text("會員")),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 48,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "請先登入以使用會員頁面",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text("返回地圖"),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final label = widget.auth.labelFor(user);
        final email = user.email?.trim();

        return Scaffold(
          appBar: AppBar(
            title: const Text("會員"),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              Card(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.construction_rounded,
                        color: theme.colorScheme.tertiary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "往下為一般 App 常見的會員／設定選項排版，給您參考；之後不要的區塊再跟我說可刪。",
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _MemberAvatarBadge(
                    photoUrl: user.photoURL,
                    theme: theme,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        FilledButton.tonalIcon(
                          onPressed: _openPersonalProfile,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text("編輯資料"),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _InfoTile(
                icon: Icons.email_outlined,
                title: "電子郵件",
                value: (email != null && email.isNotEmpty) ? email : "未設定",
              ),
              const SizedBox(height: 12),
              _InfoTile(
                icon: Icons.fingerprint_rounded,
                title: "帳戶編號（UID）",
                value: user.uid,
                monospace: true,
              ),

              /// —— 以下為常見選單區塊（參考用）————
              const SizedBox(height: 28),
              _SectionHeader(theme: theme, title: "帳號"),
              _MenuTile(
                icon: Icons.badge_outlined,
                title: "個人資料",
                subtitle: "暱稱、頭貼、自我介紹",
                onTap: _openPersonalProfile,
              ),
              _MenuTile(
                icon: Icons.password_rounded,
                title: "帳號與安全",
                subtitle: "密碼、登入紀錄、裝置管理",
                onTap: () =>
                    _memberReferenceSnack(context, "帳號與安全"),
              ),
              _MenuTile(
                icon: Icons.link_rounded,
                title: "第三方帳號綁定",
                subtitle: "Google、Apple 等（視產品需求）",
                onTap: () =>
                    _memberReferenceSnack(context, "第三方綁定"),
              ),

              const SizedBox(height: 8),
              _SectionHeader(theme: theme, title: "偏好設定"),
              _MenuTile(
                icon: Icons.notifications_outlined,
                title: "通知",
                subtitle: "推播、系統／郵件通知",
                onTap: () => _memberReferenceSnack(context, "通知設定"),
              ),
              _MenuTile(
                icon: Icons.palette_outlined,
                title: "外觀",
                subtitle: "淺色、深色或跟隨系統",
                onTap: () =>
                    _memberReferenceSnack(context, "外觀／主題"),
              ),
              _MenuTile(
                icon: Icons.map_outlined,
                title: "地圖偏好",
                subtitle: "預設縮放、單位等（地圖樣式仍於首頁設定）",
                onTap: () =>
                    _memberReferenceSnack(context, "地圖偏好"),
              ),
              _MenuTile(
                icon: Icons.language_rounded,
                title: "語言與地區",
                subtitle: "介面語言、日期格式",
                onTap: () =>
                    _memberReferenceSnack(context, "語言與地區"),
              ),

              const SizedBox(height: 8),
              _SectionHeader(theme: theme, title: "資料與隱私"),
              _MenuTile(
                icon: Icons.download_done_outlined,
                title: "下載我的資料",
                subtitle: "匯出帳號相關資料（GDPR／個資請求流程）",
                onTap: () =>
                    _memberReferenceSnack(context, "下載我的資料"),
              ),
              _MenuTile(
                icon: Icons.visibility_outlined,
                title: "隱私設定",
                subtitle: "可見範圍、活動紀錄、Cookie",
                onTap: () =>
                    _memberReferenceSnack(context, "隱私設定"),
              ),

              const SizedBox(height: 8),
              _SectionHeader(theme: theme, title: "協助與回饋"),
              _MenuTile(
                icon: Icons.help_outline_rounded,
                title: "說明中心",
                subtitle: "常見問題與操作教學",
                onTap: () =>
                    _memberReferenceSnack(context, "說明中心"),
              ),
              _MenuTile(
                icon: Icons.rate_review_outlined,
                title: "意見回饋",
                subtitle: "回報問題或建議新功能",
                onTap: () =>
                    _memberReferenceSnack(context, "意見回饋"),
              ),
              _MenuTile(
                icon: Icons.star_border_rounded,
                title: "為 App 評分",
                subtitle: "前往商店頁（若上架）",
                onTap: () =>
                    _memberReferenceSnack(context, "為 App 評分"),
              ),

              const SizedBox(height: 8),
              _SectionHeader(theme: theme, title: "關於"),
              _MenuTile(
                icon: Icons.gavel_rounded,
                title: "服務條款",
                onTap: () =>
                    _memberReferenceSnack(context, "服務條款"),
              ),
              _MenuTile(
                icon: Icons.policy_outlined,
                title: "隱私權政策",
                onTap: () =>
                    _memberReferenceSnack(context, "隱私權政策"),
              ),
              _MenuTile(
                icon: Icons.apps_rounded,
                title: "關於釣魚地圖",
                subtitle: "版本 $_demoVersionLabel",
                showChevron: false,
                onTap: () =>
                    _memberReferenceSnack(context, "關於程式"),
              ),

              const SizedBox(height: 20),
              Card(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.45,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.logout_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "登出仍請使用地圖頁右上角「登出」，以維持與 Firebase 會話一致。",
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _MemberAvatarBadge extends StatelessWidget {
  const _MemberAvatarBadge({
    required this.photoUrl,
    required this.theme,
  });

  final String? photoUrl;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl?.trim();
    const size = 64.0;
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            Icons.account_circle_rounded,
            size: size,
            color: theme.colorScheme.primary,
          ),
        ),
      );
    }
    return Icon(
      Icons.account_circle_rounded,
      size: size,
      color: theme.colorScheme.primary,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.theme,
    required this.title,
  });

  final ThemeData theme;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6, top: 6),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Icon(icon, color: scheme.primary),
        title: Text(title),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: showChevron
            ? Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
    this.monospace = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    value,
                    style: monospace
                        ? theme.textTheme.bodySmall?.copyWith(
                            fontFamily: "monospace",
                            fontFamilyFallback: const ["Consolas", "monospace"],
                          )
                        : theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
