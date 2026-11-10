import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Пользователи платформы: лимит роликов в месяц и удаление аккаунта. Видно только админу.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.myId});
  final String myId;
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<Map> _users = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.i.get('/api/admin/users') as List;
      if (mounted) setState(() => _users = r.cast<Map>());
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editLimit(Map u) async {
    final ctrl = TextEditingController(text: '${u['monthly_render_limit']}');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Лимит роликов в месяц'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${u['email']}', style: const TextStyle(color: C.muted, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Например, 3000'),
              onSubmitted: (x) => Navigator.pop(ctx, x),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Сохранить')),
        ],
      ),
    );
    if (v == null) return;
    final n = int.tryParse(v.trim().replaceAll(' ', ''));
    if (n == null || n < 0) {
      if (mounted) toast(context, 'Нужно целое число');
      return;
    }
    try {
      await Api.i.put('/api/admin/users/${u['id']}', {'monthly_render_limit': n});
      if (mounted) setState(() => u['monthly_render_limit'] = n);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _delete(Map u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: Text('Аккаунт ${u['email']} удалится вместе со всеми проектами, видео и роликами. Вернуть их будет нельзя.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.i.delete('/api/admin/users/${u['id']}');
      if (!mounted) return;
      setState(() => _users.remove(u));
      toast(context, 'Аккаунт удалён');
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final t = Theme.of(context).textTheme;
    final list = _users
        .where((u) => _query.isEmpty || '${u['email']} ${u['name']}'.toLowerCase().contains(_query))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text('Пользователи · ${_users.length}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: EdgeInsets.fromLTRB(wide ? 40 : 16, 12, wide ? 40 : 16, 40), children: [
              Content(
                maxWidth: 760,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextField(
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded, size: 20), hintText: 'Найти по почте или имени', isDense: true),
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 14),
                  for (final u in list) ...[
                    Panel(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(
                                child: Text('${u['email']}',
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                              if (u['id'] == widget.myId) ...[const SizedBox(width: 8), const Pill('это вы', color: C.violet)],
                            ]),
                            if ('${u['name'] ?? ''}'.isNotEmpty) Text('${u['name']}', style: t.bodySmall),
                            const SizedBox(height: 6),
                            Text(
                              'Роликов в этом месяце: ${u['renders_this_month']} из ${u['monthly_render_limit']} · '
                              'проектов: ${u['projects']}',
                              style: t.bodySmall,
                            ),
                          ]),
                        ),
                        TextButton(onPressed: () => _editLimit(u), child: const Text('Лимит')),
                        if (u['id'] != widget.myId)
                          IconButton(
                            tooltip: 'Удалить аккаунт',
                            icon: const Icon(Icons.delete_outline_rounded, color: C.faint, size: 20),
                            onPressed: () => _delete(u),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                  ],
                ]),
              ),
            ]),
    );
  }
}
