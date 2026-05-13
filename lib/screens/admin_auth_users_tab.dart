import "package:fishing_map/models/admin_auth_user_row.dart";
import "package:fishing_map/services/admin_auth_api.dart";
import "package:flutter/material.dart";

/// 管理員：列出 Authentication 全部使用者（Admin SDK / Callable）。
class AdminAuthUsersTab extends StatefulWidget {
  const AdminAuthUsersTab({super.key, required this.api});

  final AdminAuthApi api;

  @override
  State<AdminAuthUsersTab> createState() => _AdminAuthUsersTabState();
}

class _AdminAuthUsersTabState extends State<AdminAuthUsersTab> {
  final List<AdminAuthUserRow> _rows = [];
  String? _nextToken;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _error = null;
      _rows.clear();
      _nextToken = null;
    });
    try {
      final page = await widget.api.listUsers(maxResults: 100);
      if (!mounted) return;
      setState(() {
        _rows.addAll(page.users);
        _nextToken = page.nextPageToken;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_nextToken == null || _nextToken!.isEmpty) return;
    setState(() => _loading = true);
    try {
      final page = await widget.api.listUsers(
        maxResults: 100,
        pageToken: _nextToken,
      );
      if (!mounted) return;
      setState(() {
        _rows.addAll(page.users);
        _nextToken = page.nextPageToken;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
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
            "由 Cloud Functions + Admin SDK 列出 Firebase Authentication 使用者。"
            "點選一列可編輯信箱、顯示名稱與「新密碼」。"
            "基於安全，系統無法顯示既有密碼，只能重設新密碼。",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
            ),
          ),
        Expanded(
          child: _rows.isEmpty && _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  itemCount: _rows.length + (_nextToken != null ? 1 : 0),
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    if (i >= _rows.length) {
                      return ListTile(
                        title: const Center(child: Text("載入更多")),
                        onTap: _loading ? null : _loadMore,
                      );
                    }
                    final u = _rows[i];
                    final primaryLabel = [
                      if (u.displayName != null &&
                          u.displayName!.trim().isNotEmpty)
                        u.displayName!.trim(),
                      if (u.email != null && u.email!.trim().isNotEmpty)
                        u.email!.trim(),
                    ].join(" · ");
                    final titleText = primaryLabel.isEmpty
                        ? "（未設定顯示名稱／信箱）"
                        : primaryLabel;
                    final subParts = <String>[
                      u.uid,
                      if (u.disabled) "已停用",
                      if (u.emailVerified) "已驗證信箱",
                    ];
                    return ListTile(
                      title: Text(
                        titleText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        subParts.join(" · "),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: "monospace",
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        final changed = await Navigator.of(context).push<bool>(
                          MaterialPageRoute<bool>(
                            builder: (ctx) => AdminAuthUserEditScreen(
                              api: widget.api,
                              user: u,
                            ),
                          ),
                        );
                        if (changed == true && mounted) {
                          await _loadFirst();
                        }
                      },
                    );
                  },
                ),
        ),
        if (_loading && _rows.isNotEmpty)
          const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }
}

class AdminAuthUserEditScreen extends StatefulWidget {
  const AdminAuthUserEditScreen({
    super.key,
    required this.api,
    required this.user,
  });

  final AdminAuthApi api;
  final AdminAuthUserRow user;

  @override
  State<AdminAuthUserEditScreen> createState() => _AdminAuthUserEditScreenState();
}

class _AdminAuthUserEditScreenState extends State<AdminAuthUserEditScreen> {
  late final TextEditingController _email;
  late final TextEditingController _displayName;
  late final TextEditingController _password;
  late bool _disabled;
  late bool _emailVerified;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.user.email ?? "");
    _displayName = TextEditingController(text: widget.user.displayName ?? "");
    _password = TextEditingController();
    _disabled = widget.user.disabled;
    _emailVerified = widget.user.emailVerified;
  }

  @override
  void dispose() {
    _email.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.api.updateUser(
        uid: widget.user.uid,
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        displayName: _displayName.text.trim(),
        password: _password.text.trim().isEmpty ? null : _password.text.trim(),
        disabled: _disabled,
        emailVerified: _emailVerified,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Auth 已更新")),
      );
      Navigator.of(context).pop(true);
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
      appBar: AppBar(title: const Text("編輯 Auth 帳戶")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SelectableText(
            widget.user.uid,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: "monospace"),
          ),
          const SizedBox(height: 8),
          Text(
            "建立：${widget.user.creationTime ?? "—"}",
            style: theme.textTheme.labelSmall,
          ),
          Text(
            "上次登入：${widget.user.lastSignInTime ?? "—"}",
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: "Email",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _displayName,
            decoration: const InputDecoration(
              labelText: "顯示名稱（可留空清除）",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: "新密碼（選填，至少 6 字）",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text("停用帳號"),
            value: _disabled,
            onChanged: _busy
                ? null
                : (v) => setState(() => _disabled = v),
          ),
          SwitchListTile(
            title: const Text("標記為已驗證信箱"),
            value: _emailVerified,
            onChanged: _busy
                ? null
                : (v) => setState(() => _emailVerified = v),
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
                : const Text("儲存至 Firebase Auth"),
          ),
        ],
      ),
    );
  }
}
