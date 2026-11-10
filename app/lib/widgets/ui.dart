import 'package:flutter/material.dart';

import '../theme.dart';

void toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 30});
  final double size;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(gradient: C.grad, borderRadius: BorderRadius.circular(size * 0.3)),
          child: Icon(Icons.auto_awesome_motion_rounded, size: size * 0.6, color: Colors.white),
        ),
        SizedBox(width: size * 0.35),
        Text('Clipora', style: display(size * 0.72)),
      ]);
}

/// Карточка-поверхность с тонкой рамкой. selected — подсветка градиентной рамкой.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.selected = false,
    this.radius = 18,
    this.color = C.surface,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool selected;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final inner = Material(
      color: color,
      borderRadius: BorderRadius.circular(selected ? radius - 1.5 : radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.all(selected ? 1.5 : 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: selected ? C.grad : null,
        color: selected ? null : C.border,
        boxShadow: selected
            ? [BoxShadow(color: C.violet.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 8))]
            : null,
      ),
      child: inner,
    );
  }
}

class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, this.icon, this.onPressed, this.busy = false, this.expand = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        else if (icon != null)
          Icon(icon, size: 19, color: Colors.white),
        if (busy || icon != null) const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
      ],
    );
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: C.grad,
          borderRadius: BorderRadius.circular(12),
          boxShadow: enabled
              ? [BoxShadow(color: C.pink.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 6))]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.center,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = C.muted, this.icon, this.dot = false});
  final String text;
  final Color color;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 5)],
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.text, this.action});
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: C.surface2,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: C.border),
                ),
                child: ShaderMask(
                  shaderCallback: (r) => C.grad.createShader(r),
                  child: Icon(icon, size: 30, color: Colors.white),
                ),
              ),
              const SizedBox(height: 18),
              Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ]),
          ),
        ),
      );
}

/// Центрирует контент и ограничивает ширину на больших экранах.
class Content extends StatelessWidget {
  const Content({super.key, required this.child, this.maxWidth = 1180});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}

/// Сетка карточек: число колонок зависит от ширины.
class CardGrid extends StatelessWidget {
  const CardGrid({super.key, required this.children, this.minWidth = 300, this.gap = 14});
  final List<Widget> children;
  final double minWidth;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = (c.maxWidth / minWidth).floor().clamp(1, 4);
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final ch in children) SizedBox(width: w, child: ch)],
        );
      });
}

String formatDuration(num? sec) {
  final s = (sec ?? 0).round();
  if (s < 60) return '$s с';
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

String formatSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} КБ';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).round()} МБ';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} ГБ';
}

/// Красивый выбор из списка: поле как у ввода, меню со скруглением и галочкой у выбранного.
class ChoiceField extends StatelessWidget {
  const ChoiceField({super.key, required this.value, required this.options, required this.onChanged, this.icon});
  final String? value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      return MenuAnchor(
        alignmentOffset: const Offset(0, 6),
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(C.surface2),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(10),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: C.border),
          )),
        ),
        menuChildren: [
          for (final o in options)
            MenuItemButton(
              onPressed: () => onChanged(o),
              style: ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(box.maxWidth.isFinite ? box.maxWidth - 12 : 220, 44)),
                padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
                shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                backgroundColor: WidgetStatePropertyAll(o == value ? C.violet.withValues(alpha: 0.14) : Colors.transparent),
              ),
              trailingIcon: o == value ? const Icon(Icons.check_rounded, size: 18, color: C.violet) : null,
              child: Text(o,
                  style: TextStyle(
                      fontSize: 14, fontWeight: o == value ? FontWeight.w700 : FontWeight.w500, color: C.text)),
            ),
        ],
        builder: (context, ctl, _) => Material(
          color: C.surface2,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => ctl.isOpen ? ctl.close() : ctl.open(),
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ctl.isOpen ? C.violet : C.border),
              ),
              child: Row(children: [
                if (icon != null) ...[Icon(icon, size: 17, color: C.violet), const SizedBox(width: 8)],
                Expanded(
                  child: Text(value ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                const Icon(Icons.unfold_more_rounded, size: 18, color: C.muted),
              ]),
            ),
          ),
        ),
      );
    });
  }
}
