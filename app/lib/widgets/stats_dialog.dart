import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../theme.dart';
import 'ui.dart';

/// Охваты опубликованного ролика: по ним AI узнаёт, какие хуки у меня заходят.
Future<bool> editStats(BuildContext context, Map v) async {
  final ctl = {
    for (final k in const ['views', 'likes', 'saves']) k: TextEditingController(text: v[k] == null ? '' : '${v[k]}')
  };
  const labels = {'views': 'Просмотры', 'likes': 'Лайки', 'saves': 'Сохранения'};
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      title: const Text('Охваты ролика'),
      content: SizedBox(
        width: 340,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('«${v['hook_text']}»', style: const TextStyle(color: C.muted, fontSize: 13)),
          const SizedBox(height: 10),
          for (final k in const ['views', 'likes', 'saves'])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: ctl[k],
                autofocus: k == 'views',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: labels[k], isDense: true),
              ),
            ),
          const Text('Достаточно просмотров. Когда наберётся 5 роликов с охватами, AI начнёт предлагать больше хуков, '
              'которые у тебя заходят.',
              style: TextStyle(color: C.faint, fontSize: 12)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await Api.i.put('/api/variants/${v['id']}/stats', {
      for (final e in ctl.entries) e.key: e.value.text.isEmpty ? null : int.parse(e.value.text),
    });
    return true;
  } catch (e) {
    if (context.mounted) toast(context, e.toString());
    return false;
  }
}

String shortNum(num n) => n >= 1000000
    ? '${(n / 1000000).toStringAsFixed(1)}M'
    : n >= 1000
        ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K'
        : '$n';
