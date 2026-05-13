import "dart:async";

import "package:fishing_map/models/user_profile_extra.dart";
import "package:fishing_map/services/auth_service.dart";
import "package:fishing_map/services/user_settings_repository.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

/// 自我介紹本機快取（與 UID 綁定）；下次開頁可先顯示再上雲端校準。
String _prefsBioStorageKey(String uid) => "fishing_map.profileBio.v1.$uid";

/// 會員／帳號區塊底下的「個人資料」編輯：暱稱與頭像走 Firebase Auth，自我介紹存 Firestore。
class PersonalProfileScreen extends StatefulWidget {
  const PersonalProfileScreen({
    super.key,
    required this.auth,
    required this.profileRepo,
  });

  final AuthService auth;
  final UserSettingsRepository profileRepo;

  @override
  State<PersonalProfileScreen> createState() => _PersonalProfileScreenState();
}

class _PersonalProfileScreenState extends State<PersonalProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _photoUrl = TextEditingController();
  final _bio = TextEditingController();

  bool _saving = false;

  /// 使用者曾編輯自我介紹欄時，不因晚到的 Firestore 讀取而覆蓋輸入。
  bool _bioEdited = false;

  /// 仍有自我介紹自雲端讀取時，於欄位旁顯示小號載入指示（不阻擋整頁）。
  bool _bioLoadingFromRemote = false;

  @override
  void initState() {
    super.initState();
    final u = widget.auth.currentUser;
    if (u != null) {
      _displayName.text = u.displayName ?? "";
      _photoUrl.text = u.photoURL ?? "";
      _bioLoadingFromRemote = true;
      unawaited(_loadBioFromFirestore(u.uid));
    }
  }

  @override
  void dispose() {
    _displayName.dispose();
    _photoUrl.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _loadBioFromFirestore(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _prefsBioStorageKey(uid);
      final cached = prefs.getString(key);
      // 本機快取先出字，避免等 Firestore 線路（上線後仍可能偶發慢封包）
      if (cached != null && mounted && !_bioEdited) {
        _bio.text = cached;
        setState(() => _bioLoadingFromRemote = false);
      }
    } catch (_) {}

    try {
      final extra =
          await widget.profileRepo.loadProfileExtra(uid);
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsBioStorageKey(uid), extra.bio);
      if (!_bioEdited) {
        setState(() => _bio.text = extra.bio);
      }
    } catch (_) {
      // 離線／規則錯誤時仍可使用暱稱與頭像（Auth）；本機快取已盡力顯示。
    } finally {
      if (mounted) {
        setState(() => _bioLoadingFromRemote = false);
      }
    }
  }

  String? _validatePhotoUrl(String? value) {
    final s = value?.trim() ?? "";
    if (s.isEmpty) return null;
    final uri = Uri.tryParse(s);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != "http" && uri.scheme != "https")) {
      return "請輸入有效的 http 或 https 圖片連結（或留空）";
    }
    return null;
  }

  String _glyphFrom(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return "?";
    final it = t.runes.iterator;
    if (!it.moveNext()) return "?";
    return String.fromCharCode(it.current).toUpperCase();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = widget.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("已登出，請重新登入")),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.auth.updateUserProfile(
        displayName: _displayName.text.trim(),
        photoUrl: _photoUrl.text.trim(),
      );
      await widget.profileRepo.saveProfileExtra(
        user.uid,
        UserProfileExtra(bio: _bio.text),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsBioStorageKey(user.uid),
        _bio.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("個人資料已儲存"),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("儲存失敗：$e"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<User?>(
      stream: widget.auth.authChanges,
      builder: (context, snap) {
        if (snap.data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text("個人資料")),
            body: const Center(child: Text("請先登入")),
          );
        }

        final user = snap.data!;

        final previewUrl = _photoUrl.text.trim().isEmpty
            ? user.photoURL
            : _photoUrl.text.trim();
        final glyph = _displayName.text.trim().isNotEmpty
            ? _glyphFrom(_displayName.text)
            : _glyphFrom(user.email ?? user.uid);

        return Scaffold(
          appBar: AppBar(
            title: const Text("個人資料"),
            actions: [
              if (!_saving)
                TextButton(
                  onPressed: _save,
                  child: const Text("儲存"),
                ),
            ],
          ),
          body: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    children: [
                      Center(
                        child: _AvatarPreview(
                          photoUrl: previewUrl,
                          fallbackGlyph: glyph,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "儲存後頭像會依「頭像連結」更新；連結無效或圖檔不可用時將顯示預設圖示。",
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _displayName,
                        decoration: const InputDecoration(
                          labelText: "顯示名稱（暱稱）",
                          hintText: "其他使用者可看到的稱呼",
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                        maxLength: 80,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _photoUrl,
                        decoration: const InputDecoration(
                          labelText: "頭像圖片連結（選填）",
                          hintText: "https://…（公開可讀的圖檔網址）",
                          border: OutlineInputBorder(),
                          helperText:
                              "留空並儲存可清除頭像。需有可連線的完整圖檔網址。",
                        ),
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        validator: _validatePhotoUrl,
                        maxLength: 2048,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _bio,
                        decoration: InputDecoration(
                          labelText: "自我介紹（選填）",
                          hintText: "簡短介紹自己或常用的釣法、區域等",
                          alignLabelWithHint: true,
                          border: const OutlineInputBorder(),
                          suffixIcon: _bioLoadingFromRemote
                              ? const Padding(
                                  padding:
                                      EdgeInsets.only(right: 8, bottom: 8),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : null,
                        ),
                        maxLines: 5,
                        maxLength: 500,
                        onChanged: (_) {
                          setState(() => _bioEdited = true);
                        },
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.mail_outline_rounded,
                          color: theme.colorScheme.primary,
                        ),
                        title: const Text("登入信箱"),
                        subtitle: Text(user.email ?? "（無）"),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.onInverseSurface,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_saving ? "儲存中…" : "儲存變更"),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
          );
      },
    );
  }
}

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({
    required this.photoUrl,
    required this.fallbackGlyph,
  });

  final String? photoUrl;
  final String fallbackGlyph;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const size = 96.0;
    final url = photoUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return _fallbackCircle(scheme, size);
          },
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              width: size,
              height: size,
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                ),
              ),
            );
          },
        ),
      );
    }
    return _fallbackCircle(scheme, size);
  }

  Widget _fallbackCircle(ColorScheme scheme, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        fallbackGlyph,
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
