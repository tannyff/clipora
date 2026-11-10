import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await Api.i.post(_register ? '/api/auth/register' : '/api/auth/login', {
        'email': _email.text,
        'password': _pass.text,
        if (_register) 'name': _name.text,
      });
      await Api.i.setToken(res['token'] as String);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final form = _form(context);
    return Scaffold(
      body: wide
          ? Row(children: [
              Expanded(child: _hero(context, true)),
              Expanded(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(32), child: form))),
            ])
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(children: [_hero(context, false), const SizedBox(height: 20), form]),
              ),
            ),
    );
  }

  Widget _hero(BuildContext context, bool wide) {
    final points = [
      (Icons.graphic_eq_rounded, 'Расшифровка речи прямо на твоём компьютере'),
      (Icons.auto_awesome_rounded, 'AI находит темы и пишет разные хуки'),
      (Icons.verified_rounded, 'Анализатор проверяет, что ролики не копии'),
    ];
    return Container(
      margin: wide ? const EdgeInsets.all(16) : EdgeInsets.zero,
      padding: EdgeInsets.all(wide ? 48 : 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF241A4D), Color(0xFF15111F), Color(0xFF3A1430)],
        ),
        border: Border.all(color: C.border),
      ),
      child: Column(
        mainAxisAlignment: wide ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Logo(size: 34),
          SizedBox(height: wide ? 0 : 28),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ShaderMask(
              shaderCallback: (r) => const LinearGradient(colors: [Colors.white, Color(0xFFE6DEFF)]).createShader(r),
              child: Text('Одна съёмка —\nдесятки роликов', style: display(wide ? 52 : 34)),
            ),
            const SizedBox(height: 14),
            Text(
              'Загрузи видео, а Clipora разрежет его на самостоятельные рилсы с разными хуками и субтитрами.',
              style: TextStyle(fontSize: wide ? 17 : 15, color: C.muted, height: 1.5),
            ),
            const SizedBox(height: 26),
            for (final p in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(p.$1, size: 18, color: C.pink),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(p.$2, style: const TextStyle(fontWeight: FontWeight.w500))),
                ]),
              ),
          ]),
          if (wide) Text('Для авторов, экспертов и SMM', style: TextStyle(color: C.faint, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _form(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_register ? 'Создать аккаунт' : 'С возвращением', style: display(30)),
          const SizedBox(height: 8),
          Text(_register ? 'Пара секунд, и можно загружать видео.' : 'Войди, чтобы продолжить работу с роликами.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 14)),
          const SizedBox(height: 28),
          AutofillGroup(
            child: Column(children: [
              if (_register) ...[
                TextField(
                  controller: _name,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(labelText: 'Имя'),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: 'Пароль'),
                onSubmitted: (_) => _submit(),
              ),
            ]),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Text(_error!, style: const TextStyle(color: C.red, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 22),
          GradientButton(
            label: _register ? 'Создать аккаунт' : 'Войти',
            onPressed: _submit,
            busy: _busy,
            expand: true,
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => setState(() {
              _register = !_register;
              _error = null;
            }),
            child: Text(_register ? 'Уже есть аккаунт? Войти' : 'Нет аккаунта? Зарегистрироваться'),
          ),
        ],
      ),
    );
  }
}
