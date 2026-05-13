import "package:fishing_map/services/auth_service.dart";
import "package:flutter/material.dart";

class AuthPopupPanel extends StatefulWidget {
  const AuthPopupPanel({
    super.key,
    required this.auth,
  });

  final AuthService auth;

  @override
  State<AuthPopupPanel> createState() => _AuthPopupPanelState();
}

class _AuthPopupPanelState extends State<AuthPopupPanel> {
  // TODO(REMOVE): 開發省事，空白郵件自動帶入；上線前刪除此常數與下方邏輯。
  static const _kDevDefaultEmailIfBlank = "admin@a.com";

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _email.text.trim().isEmpty
        ? _kDevDefaultEmailIfBlank
        : _email.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await widget.auth.registerWithEmail(email, _password.text);
      } else {
        await widget.auth.signInWithEmail(email, _password.text);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 320,
      child: DecoratedBox(
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
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.account_circle_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _register ? "註冊帳號" : "登入帳號",
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: "電子郵件",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? "";
                    if (t.isNotEmpty && !t.contains("@")) return "格式不正確";
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "密碼",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) {
                    if (v == null || v.length < 6) return "至少 6 碼";
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_register ? "建立帳號" : "登入"),
                ),
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _register = !_register),
                  child: Text(_register ? "改為登入" : "沒有帳號？註冊"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
