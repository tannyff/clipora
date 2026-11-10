import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'admin_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<dynamic> _items = [];
  Map<String, dynamic>? _me;
  final _name = TextEditingController();
  bool _trial = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([Api.i.get('/api/destinations'), Api.i.get('/api/me')]);
      if (!mounted) return;
      setState(() {
        _items = r[0] as List;
        _me = (r[1] as Map).cast<String, dynamic>();
      });
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _add() async {
    if (_name.text.trim().isEmpty) return;
    try {
      await Api.i.post('/api/destinations', {'name': _name.text, 'kind': _trial ? 'trial' : 'account'});
      _name.clear();
      _load();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _edit(Map d) async {
    final ctl = TextEditingController(text: d['name'] as String);
    var trial = d['kind'] == 'trial';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: C.surface,
          title: const Text('Название'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: ctl, autofocus: true, onSubmitted: (_) => Navigator.pop(ctx, true)),
            const SizedBox(height: 12),
            FilterChip(label: const Text('Пробные рилсы'), selected: trial, onSelected: (v) => setD(() => trial = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await Api.i.put('/api/destinations/${d['id']}', {'name': ctl.text, 'kind': trial ? 'trial' : 'account'});
      _load();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _delete(String id) async {
    await Api.i.delete('/api/destinations/$id');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final t = Theme.of(context).textTheme;
    final used = (_me?['renders_this_month'] as int?) ?? 0;
    final limit = (_me?['monthly_render_limit'] as int?) ?? 1;

    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 40 : 20, wide ? 36 : 12, wide ? 40 : 20, 40),
      children: [
        Content(
          maxWidth: 760,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Настройки', style: display(wide ? 34 : 28)),
            const SizedBox(height: 24),
            if (_me?['is_admin'] == true) ...[
              Panel(
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => AdminScreen(myId: _me!['id'] as String))).then((_) => _load()),
                child: Row(children: [
                  const Icon(Icons.admin_panel_settings_outlined, color: C.violet),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Админ-панель: пользователи и лимиты', style: t.titleSmall)),
                  const Icon(Icons.chevron_right_rounded, color: C.muted),
                ]),
              ),
              const SizedBox(height: 14),
            ],
            if (_me != null)
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: C.violet.withValues(alpha: 0.2),
                      child: Text(
                        ((_me!['name'] as String?)?.isNotEmpty == true ? _me!['name'] as String : _me!['email'] as String)
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w700, color: C.violet),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if ((_me!['name'] as String?)?.isNotEmpty == true) Text(_me!['name'] as String, style: t.titleMedium),
                        Text(_me!['email'] as String, style: t.bodySmall),
                      ]),
                    ),
                    Pill('Тариф ${_me!['plan']}', color: C.violet),
                  ]),
                  const SizedBox(height: 20),
                  Row(children: [
                    Text('Роликов в этом месяце', style: t.bodySmall),
                    const Spacer(),
                    Text('$used из $limit', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: (used / limit).clamp(0, 1).toDouble(), minHeight: 6),
                  ),
                ]),
              ),
            const SizedBox(height: 32),
            Text('Куда выкладываешь ролики', style: t.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Нажми на название, чтобы переименовать. При выгрузке ролика ты выбираешь одно из этих мест. Анализатор сравнивает каждый новый ролик '
              'со всеми выгруженными, чтобы на аккаунты не ушли похожие.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 16),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final (i, d) in _items.indexed) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: (d['kind'] == 'trial' ? C.yellow : C.violet).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        d['kind'] == 'trial' ? Icons.science_outlined : Icons.alternate_email_rounded,
                        size: 19,
                        color: d['kind'] == 'trial' ? C.yellow : C.violet,
                      ),
                    ),
                    title: Text(d['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(d['kind'] == 'trial' ? 'Пробные рилсы' : 'Аккаунт', style: t.bodySmall),
                    onTap: () => _edit(d as Map),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Переименовать',
                        icon: const Icon(Icons.edit_outlined, color: C.muted, size: 19),
                        onPressed: () => _edit(d as Map),
                      ),
                      IconButton(
                        tooltip: 'Удалить',
                        icon: const Icon(Icons.close_rounded, color: C.faint, size: 20),
                        onPressed: () => _delete(d['id'] as String),
                      ),
                    ]),
                  ),
                ],
                if (_items.isNotEmpty) const Divider(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: wide ? 300 : double.infinity,
                        child: TextField(
                          controller: _name,
                          decoration: const InputDecoration(hintText: 'Например, @tannyff_m', isDense: true),
                          onSubmitted: (_) => _add(),
                        ),
                      ),
                      FilterChip(
                        label: const Text('Пробные рилсы'),
                        selected: _trial,
                        onSelected: (v) => setState(() => _trial = v),
                      ),
                      FilledButton(onPressed: _add, child: const Text('Добавить')),
                    ],
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ],
    );
  }
}
