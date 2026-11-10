import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'ui.dart';

/// Возвращает новое название, если переименование прошло.
Future<String?> renameProject(BuildContext context, String id, String current) async {
  final ctrl = TextEditingController(text: current)..selection = TextSelection(baseOffset: 0, extentOffset: current.length);
  final title = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Переименовать проект'),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(hintText: 'Название проекта'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Сохранить')),
      ],
    ),
  );
  final t = title?.trim() ?? '';
  if (t.isEmpty || t == current) return null;
  try {
    final r = await Api.i.put('/api/projects/$id', {'title': t});
    return r['title'] as String;
  } catch (e) {
    if (context.mounted) toast(context, e.toString());
    return null;
  }
}

/// true — проект удалён.
Future<bool> deleteProject(BuildContext context, String id, String title) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Удалить проект?'),
      content: Text('Проект «$title» удалится вместе со всеми исходниками, вариантами и готовыми роликами. '
          'Вернуть их будет нельзя.'),
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
  if (ok != true) return false;
  try {
    await Api.i.delete('/api/projects/$id');
    return true;
  } catch (e) {
    if (context.mounted) toast(context, e.toString());
    return false;
  }
}

class ProjectMenu extends StatelessWidget {
  const ProjectMenu({super.key, required this.onRename, required this.onDelete, this.color});
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final Color? color;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Действия с проектом',
        icon: Icon(Icons.more_vert_rounded, color: color),
        onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'rename',
            child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 10), Text('Переименовать')]),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: C.red),
              SizedBox(width: 10),
              Text('Удалить проект', style: TextStyle(color: C.red)),
            ]),
          ),
        ],
      );
}
