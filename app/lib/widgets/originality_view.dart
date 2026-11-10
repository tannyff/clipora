import 'package:flutter/material.dart';

import '../theme.dart';

const levels = {
  'green': (C.green, 'Новый ролик', Icons.verified_rounded),
  'yellow': (C.yellow, 'Похоже на другие', Icons.info_rounded),
  'red': (C.red, 'Почти копия', Icons.block_rounded),
};

class OriginalityView extends StatelessWidget {
  const OriginalityView({super.key, required this.report, this.compact = false});
  final Map<String, dynamic> report;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (color, label, icon) = levels[report['level']] ?? levels['yellow']!;
    final tips = (report['tips'] as List? ?? const []).cast<String>();
    final near = report['near_copy'] as Map? ?? const {};
    final shownTips = compact ? tips.take(2) : tips;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
          const Spacer(),
          Text('${report['total']}',
              style: TextStyle(fontFamily: 'InterDisplay', fontWeight: FontWeight.w800, fontSize: 20, color: color)),
          Text(' / 100', style: t.bodySmall),
        ]),
        const SizedBox(height: 12),
        _bar('Монтаж', report['structure']?['score'], color),
        _bar('Сценарий', report['script']?['score'], color),
        _bar('Авторское', report['authorial']?['score'], color),
        if ((near['compared_with'] ?? 0) > 0) ...[
          const SizedBox(height: 6),
          Text(
            'Совпадение с выгруженными: ${(((near['max_overlap'] ?? 0) as num) * 100).round()}%',
            style: t.bodySmall,
          ),
        ],
        for (final tip in shownTips)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(tip, style: t.bodySmall?.copyWith(color: C.text.withValues(alpha: 0.85)))),
            ]),
          ),
      ]),
    );
  }

  Widget _bar(String name, Object? score, Color color) {
    final v = ((score as num?) ?? 0).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(width: 78, child: Text(name, style: const TextStyle(fontSize: 12, color: C.muted))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: v / 100,
              minHeight: 5,
              color: color,
              backgroundColor: C.surface2,
            ),
          ),
        ),
        SizedBox(
          width: 30,
          child: Text('${v.round()}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: C.muted)),
        ),
      ]),
    );
  }
}
