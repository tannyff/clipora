import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/stats_dialog.dart';
import '../widgets/ui.dart';

/// Контент-план: готовые ролики раскладываются по дням (перетаскиванием) и аккаунтам.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, required this.visible});
  final bool visible;
  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

const _days = 14;
const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
const _months = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];

String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

class _PlanScreenState extends State<PlanScreen> {
  late DateTime _from = DateUtils.dateOnly(DateTime.now());
  List<Map> _planned = [], _free = [];
  List _destinations = [];
  Map _stats = {};
  bool _loading = true;

  @override
  void didUpdateWidget(PlanScreen old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible) _load();
  }

  @override
  void initState() {
    super.initState();
    if (widget.visible) _load();
  }

  Future<void> _load() async {
    try {
      final to = _from.add(const Duration(days: _days - 1));
      final r = await Future.wait([
        Api.i.get('/api/plan?from=${_iso(_from)}&to=${_iso(to)}'),
        Api.i.get('/api/destinations'),
        Api.i.get('/api/stats'),
      ]);
      if (!mounted) return;
      setState(() {
        _planned = ((r[0] as Map)['planned'] as List).cast<Map>();
        _free = ((r[0] as Map)['free'] as List).cast<Map>();
        _destinations = r[1] as List;
        _stats = r[2] as Map;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        toast(context, e.toString());
      }
    }
  }

  Future<void> _put(Map v, {DateTime? day, bool clear = false, String? destination}) async {
    try {
      await Api.i.put('/api/variants/${v['id']}/plan', {
        'date': clear ? null : _iso(day ?? DateTime.parse('${v['planned_on']}'.substring(0, 10))),
        if (destination != null) 'destination': destination,
      });
      await _load();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  void _copy(Map v) {
    final tags = ((v['hashtags'] as List?) ?? const []).join(' ');
    Clipboard.setData(ClipboardData(text: '${v['caption'] ?? ''}\n\n$tags'.trim()));
    toast(context, 'Описание скопировано');
  }

  Future<void> _togglePublished(Map v) async {
    try {
      await Api.i.put('/api/variants/${v['id']}/published', {'published': v['published_at'] == null});
      await _load();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  // ---------- Карточки ----------

  Widget _mini(Map v, {required bool inPlan}) {
    final id = v['id'] as String;
    final published = v['published_at'] != null;
    final names = [for (final d in _destinations) d['name'] as String];
    return Container(
      width: 230,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: C.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: published ? C.green : C.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 44,
            height: 78,
            child: Image.network(Api.i.thumbUrl(id, v['rendered_at']),
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: C.surface)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('«${v['hook_text']}»', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 2),
            PopupMenuButton<String>(
              tooltip: 'Аккаунт',
              onSelected: (d) => inPlan ? _put(v, destination: d) : _put(v, clear: true, destination: d),
              itemBuilder: (_) => [for (final n in names) PopupMenuItem(value: n, child: Text(n))],
              child: Text('${v['destination'] ?? 'выбрать аккаунт'} ▾',
                  style: const TextStyle(fontSize: 11.5, color: C.violet)),
            ),
            Row(children: [
              _icon(Icons.copy_rounded, 'Скопировать описание', () => _copy(v)),
              if (inPlan)
                _icon(published ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    published ? 'Снять отметку' : 'Опубликовала', () => _togglePublished(v),
                    color: published ? C.green : null),
              if (published)
                _icon(Icons.bar_chart_rounded, v['views'] == null ? 'Внести охваты' : '${v['views']} просмотров', () async {
                  if (await editStats(context, v)) _load();
                }),
              if (inPlan) _icon(Icons.close_rounded, 'Убрать из плана', () => _put(v, clear: true)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _icon(IconData i, String tip, VoidCallback onTap, {Color? color}) => IconButton(
        tooltip: tip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        icon: Icon(i, size: 17, color: color ?? C.muted),
      );

  // На компьютере тянут мышкой сразу, на телефоне — долгим нажатием, чтобы не мешать прокрутке.
  Widget _draggable(Map v, {required bool inPlan}) {
    final card = _mini(v, inPlan: inPlan);
    final feedback = Material(color: Colors.transparent, child: Opacity(opacity: 0.85, child: card));
    final ghost = Opacity(opacity: 0.35, child: card);
    return isWide(context)
        ? Draggable<Map>(data: v, feedback: feedback, childWhenDragging: ghost, child: card)
        : LongPressDraggable<Map>(data: v, feedback: feedback, childWhenDragging: ghost, child: card);
  }

  Widget _day(DateTime day) {
    final items = [for (final v in _planned) if ('${v['planned_on']}'.startsWith(_iso(day))) v];
    final today = DateUtils.isSameDay(day, DateTime.now());
    return DragTarget<Map>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => _put(d.data, day: day),
      builder: (_, cand, __) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cand.isNotEmpty ? C.violet.withValues(alpha: 0.12) : C.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cand.isNotEmpty || today ? C.violet : C.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('${_weekdays[day.weekday - 1]}, ${day.day} ${_months[day.month - 1]}',
                style: TextStyle(fontWeight: FontWeight.w700, color: today ? C.violet : C.text)),
            if (today) const Text('  · сегодня', style: TextStyle(color: C.violet, fontSize: 12)),
            const Spacer(),
            Text(items.isEmpty ? '' : '${items.length}', style: const TextStyle(color: C.muted, fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Text('Перетащи сюда ролик', style: TextStyle(color: C.faint, fontSize: 12.5))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [for (final v in items) _draggable(v, inPlan: true)]),
        ]),
      ),
    );
  }

  // ---------- Статистика ----------

  Widget _statsPanel() {
    final total = (_stats['total'] as num?)?.toInt() ?? 0;
    final types = ((_stats['hook_types'] as List?) ?? const []).cast<Map>();
    final best = types.isEmpty ? 1 : types.map((t) => (t['views'] as num?) ?? 0).reduce((a, b) => a > b ? a : b);
    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Что заходит', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 6),
        if (total < 5)
          Text(
              'Внеси просмотры опубликованных роликов (кнопка со столбиками на карточке) — '
              'с 5 роликов AI начнёт предлагать больше хуков, которые у тебя заходят. Сейчас: $total.',
              style: const TextStyle(color: C.muted, fontSize: 12.5))
        else ...[
          Text('По $total роликам — средние просмотры по типу хука. AI уже учитывает это в новых вариантах.',
              style: const TextStyle(color: C.muted, fontSize: 12.5)),
          const SizedBox(height: 10),
          for (final t in types)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                SizedBox(width: 92, child: Text('${t['key']}', style: const TextStyle(fontSize: 12.5))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: best == 0 ? 0 : ((t['views'] as num?) ?? 0) / best,
                      minHeight: 8,
                      backgroundColor: C.surface2,
                      color: C.violet,
                    ),
                  ),
                ),
                SizedBox(
                    width: 96,
                    child: Text('  ${shortNum((t['views'] as num?) ?? 0)} · ${t['n']} шт',
                        style: const TextStyle(fontSize: 12, color: C.muted))),
              ]),
            ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final pad = EdgeInsets.fromLTRB(wide ? 40 : 16, wide ? 28 : 12, wide ? 40 : 16, 40);
    if (_loading) return const Center(child: CircularProgressIndicator());
    final to = _from.add(const Duration(days: _days - 1));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: pad, children: [
        Content(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Контент-план', style: display(wide ? 28 : 22))),
              IconButton(
                tooltip: 'Раньше',
                onPressed: () {
                  setState(() => _from = _from.subtract(const Duration(days: 7)));
                  _load();
                },
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text('${from(_from)} — ${from(to)}', style: const TextStyle(color: C.muted, fontSize: 13)),
              IconButton(
                tooltip: 'Позже',
                onPressed: () {
                  setState(() => _from = _from.add(const Duration(days: 7)));
                  _load();
                },
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ]),
            const SizedBox(height: 12),
            _statsPanel(),
            const SizedBox(height: 16),
            Text('Готовы, но ещё не в плане: ${_free.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(wide ? 'Тяни ролик мышкой в нужный день.' : 'Зажми ролик и перетащи в нужный день.',
                style: const TextStyle(color: C.muted, fontSize: 12.5)),
            const SizedBox(height: 8),
            // Сюда можно вернуть ролик из плана.
            DragTarget<Map>(
              onAcceptWithDetails: (d) => _put(d.data, clear: true),
              builder: (_, cand, __) => Container(
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cand.isNotEmpty ? C.violet : Colors.transparent),
                ),
                child: _free.isEmpty
                    ? const Center(
                        child: Text('Все готовые ролики уже в плане', style: TextStyle(color: C.faint, fontSize: 12.5)))
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _free.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => _draggable(_free[i], inPlan: false),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < _days; i++) _day(_from.add(Duration(days: i))),
          ]),
        ),
      ]),
    );
  }

  String from(DateTime d) => '${d.day} ${_months[d.month - 1]}';
}
