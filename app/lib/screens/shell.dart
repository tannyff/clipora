import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/queue_bar.dart';
import '../widgets/ui.dart';
import 'accounts_screen.dart';
import 'library_screen.dart';
import 'plan_screen.dart';
import 'projects_screen.dart';
import 'settings_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  static const _items = [
    (Icons.video_library_outlined, Icons.video_library_rounded, 'Проекты'),
    (Icons.folder_outlined, Icons.folder_rounded, 'Аккаунты'),
    (Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'План'),
    (Icons.movie_filter_outlined, Icons.movie_filter_rounded, 'Вставки'),
    (Icons.tune_outlined, Icons.tune_rounded, 'Настройки'),
  ];

  Future<void> _logout() async {
    try {
      await Api.i.post('/api/auth/logout');
    } catch (_) {}
    await Api.i.setToken(null);
  }

  @override
  Widget build(BuildContext context) {
    final page = IndexedStack(index: _tab, children: [
      const ProjectsScreen(),
      AccountsScreen(visible: _tab == 1),
      PlanScreen(visible: _tab == 2),
      const LibraryScreen(),
      const SettingsScreen(),
    ]);

    if (!isWide(context)) {
      return Scaffold(
        appBar: AppBar(
          titleSpacing: 20,
          title: const Logo(size: 26),
          actions: [
            IconButton(tooltip: 'Выйти', onPressed: _logout, icon: const Icon(Icons.logout_rounded, color: C.muted)),
            const SizedBox(width: 6),
          ],
        ),
        body: Column(children: [
          const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 0), child: QueueBar()),
          Expanded(child: page),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            for (final it in _items) NavigationDestination(icon: Icon(it.$1), selectedIcon: Icon(it.$2), label: it.$3),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(children: [
        Container(
          width: 248,
          decoration: const BoxDecoration(
            color: C.surface,
            border: Border(right: BorderSide(color: C.border)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(left: 8), child: Logo(size: 30)),
            const SizedBox(height: 32),
            for (final (i, it) in _items.indexed) _navItem(i, it.$1, it.$2, it.$3),
            const Spacer(),
            const QueueBar(),
            const SizedBox(height: 10),
            _navTile(Icons.logout_rounded, 'Выйти', false, _logout),
          ]),
        ),
        Expanded(child: page),
      ]),
    );
  }

  Widget _navItem(int i, IconData icon, IconData active, String label) =>
      _navTile(_tab == i ? active : icon, label, _tab == i, () => setState(() => _tab = i));

  Widget _navTile(IconData icon, String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: selected ? C.violet.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(children: [
                Icon(icon, size: 20, color: selected ? C.violet : C.muted),
                const SizedBox(width: 12),
                Text(label,
                    style: TextStyle(fontWeight: FontWeight.w600, color: selected ? C.text : C.muted, fontSize: 14)),
              ]),
            ),
          ),
        ),
      );
}
