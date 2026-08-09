import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/theme_controller.dart';
import 'login_page.dart';
import 'main_page.dart';

/// 注册页：用户名唯一 + 密码一致性校验，成功后进入主界面。
class RegisterPage extends StatefulWidget {
  final AuthService? authService;

  const RegisterPage({super.key, this.authService});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  late final AuthService _auth = widget.authService ?? AuthService();
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final result = await _auth.register(
      username: _usernameController.text,
      password: _passwordController.text,
      nickname: _nicknameController.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? '注册失败')),
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            MainPage(authService: _auth, theme: ThemeScope.of(context)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('注册')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _usernameController,
                  // 荣耀等机型 IME 对带自动纠正/联想标志的普通字段不弹软键盘，
                  // 与可用的密码字段对齐，关闭 autocorrect/enableSuggestions
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: '用户名（唯一）',
                    helperText: '不能包含中文，昵称可自由设置',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final name = v?.trim() ?? '';
                    if (name.isEmpty) return '用户名不能为空';
                    if (name.contains(RegExp(r'[\u4e00-\u9fff]'))) {
                      return '用户名不能包含中文';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: '密码（至少 6 位）',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.length < 6 ? '密码至少 6 位' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmController,
                  obscureText: _obscure,
                  decoration: const InputDecoration(
                    labelText: '确认密码',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v != _passwordController.text
                      ? '两次输入的密码不一致'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nicknameController,
                  // 与用户名同理：关闭自动纠正/联想，保证荣耀机型软键盘可弹出
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: '昵称（可选）',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('注册'),
                  ),
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => LoginPage(authService: _auth),
                    ),
                  ),
                  child: const Text('已有账号？去登录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
