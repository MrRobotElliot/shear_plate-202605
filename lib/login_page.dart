import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 登录：手机号 + 密码或短信验证码（二选一），或邮箱登录（邮箱 + 密码）。
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('登录'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '手机号登录'),
              Tab(text: '邮箱登录'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PhoneLoginTab(),
            _EmailLoginTab(),
          ],
        ),
      ),
    );
  }
}

enum _PhoneCredential { password, smsCode }

class _PhoneLoginTab extends StatefulWidget {
  const _PhoneLoginTab();

  @override
  State<_PhoneLoginTab> createState() => _PhoneLoginTabState();
}

class _PhoneLoginTabState extends State<_PhoneLoginTab> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _smsCode = TextEditingController();
  bool _obscurePassword = true;
  _PhoneCredential _credential = _PhoneCredential.password;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _smsCode.dispose();
    super.dispose();
  }

  void _setCredential(_PhoneCredential next) {
    if (_credential == next) return;
    setState(() {
      _credential = next;
      if (_credential == _PhoneCredential.password) {
        _smsCode.clear();
      } else {
        _password.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    Widget underlineLabel(String text, bool selected, VoidCallback onTap) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                height: 3,
                width: selected ? 48 : 0,
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d+\s-]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: '手机号',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone_android_outlined),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return '请输入手机号';
                        if (v.replaceAll(RegExp(r'\D'), '').length < 11) {
                          return '请输入有效手机号';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_credential == _PhoneCredential.password)
                      TextFormField(
                        controller: _password,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: '密码',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () {
                              setState(() => _obscurePassword = !_obscurePassword);
                            },
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return '请输入密码';
                          if (v.length < 6) return '密码至少 6 位';
                          return null;
                        },
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _smsCode,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '短信验证码',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.sms_outlined),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return '请输入验证码';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: OutlinedButton(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('短信验证码已发送（演示）')),
                                );
                              },
                              child: const Text('获取验证码'),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () {
                        if (_formKey.currentState?.validate() ?? false) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('登录接口待接入')),
                          );
                        }
                      },
                      child: const Text('登录'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 20 + bottomSafe),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              underlineLabel(
                '密码',
                _credential == _PhoneCredential.password,
                () => _setCredential(_PhoneCredential.password),
              ),
              underlineLabel(
                '验证码',
                _credential == _PhoneCredential.smsCode,
                () => _setCredential(_PhoneCredential.smsCode),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmailLoginTab extends StatefulWidget {
  const _EmailLoginTab();

  @override
  State<_EmailLoginTab> createState() => _EmailLoginTabState();
}

class _EmailLoginTabState extends State<_EmailLoginTab> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: '邮箱',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return '请输入邮箱';
                  if (!v.contains('@')) return '邮箱格式不正确';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: '密码',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return '请输入密码';
                  if (v.length < 6) return '密码至少 6 位';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  if (_formKey.currentState?.validate() ?? false) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('登录接口待接入')),
                    );
                  }
                },
                child: const Text('登录'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
