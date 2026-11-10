import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/project_actions.dart';
import '../widgets/ui.dart';
import 'project_screen.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<dynamic> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Api.i.get('/api/projects');
      if (mounted) setState(() => _projects = res as List);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final ctrl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый проект'),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Например, «Ноябрь, съёмка 1»'),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Создать')),
        ],
      ),
    );
    if (title == null) return;
    try {
      final p = await Api.i.post('/api/projects', {'title': title});
      await _load();
      if (mounted) _open(p['id'] as String);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _open(String id) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectScreen(projectId: id)));
    _load();
  }

  Future<void> _rename(Map p) async {
    final t = await renameProject(context, p['id'] as String, p['title'] as String);
    if (t != null && mounted) setState(() => p['title'] = t);
  }

  Future<void> _delete(Map p) async {
    if (await deleteProject(context, p['id'] as String, p['title'] as String) && mounted) {
      toast(context, 'Проект удалён');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    final header = Padding(
      padding: EdgeInsets.fromLTRB(wide ? 40 : 20, wide ? 36 : 12, wide ? 40 : 20, 20),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Проекты', style: display(wide ? 34 : 28)),
            const SizedBox(height: 4),
            Text('Один проект — одна съёмка или серия на одну тему',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        if (_projects.isNotEmpty)
          GradientButton(label: wide ? 'Новый проект' : 'Новый', icon: Icons.add_rounded, onPressed: _create),
      ]),
    );

    if (_projects.isEmpty) {
      return Column(children: [
        header,
        Expanded(
          child: EmptyState(
            icon: Icons.movie_filter_rounded,
            title: 'Здесь будут твои съёмки',
            text: 'Создай проект и загрузи в него видео. Clipora расшифрует речь и предложит варианты роликов.',
            action: GradientButton(label: 'Создать первый проект', icon: Icons.add_rounded, onPressed: _create),
          ),
        ),
      ]);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Content(child: header),
          Content(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20),
              child: CardGrid(minWidth: 280, children: [for (final p in _projects) _card(p)]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Map p) {
    final busy = (p['proposed'] as int? ?? 0) == 0 && (p['sources'] as int? ?? 0) > 0;
    return Panel(
      padding: EdgeInsets.zero,
      onTap: () => _open(p['id'] as String),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 96,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [C.violet.withValues(alpha: 0.35), C.pink.withValues(alpha: 0.18)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Expanded(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Icon(Icons.movie_creation_outlined, color: Colors.white70),
              ),
            ),
            ProjectMenu(color: Colors.white70, onRename: () => _rename(p), onDelete: () => _delete(p)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['title'] as String,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              Pill('${p['sources']} исх.', icon: Icons.videocam_outlined),
              Pill('${p['proposed']} вариантов', color: C.violet, icon: Icons.auto_awesome_rounded),
              Pill('${p['ready']} роликов', color: C.green, icon: Icons.check_rounded),
              if (busy) const Pill('в работе', color: C.yellow, dot: true),
            ]),
          ]),
        ),
      ]),
    );
  }
}
