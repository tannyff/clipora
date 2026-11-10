import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFF0B0B10);
  static const surface = Color(0xFF14141C);
  static const surface2 = Color(0xFF1C1C27);
  static const border = Color(0xFF272736);
  static const text = Color(0xFFF4F3FA);
  static const muted = Color(0xFF9B99B0);
  static const faint = Color(0xFF6B6980);
  static const violet = Color(0xFF8B6CFF);
  static const pink = Color(0xFFFF5C9A);
  static const green = Color(0xFF3DDC97);
  static const yellow = Color(0xFFFFC94D);
  static const red = Color(0xFFFF5C72);

  static const grad = LinearGradient(
    colors: [violet, pink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

const wideBreakpoint = 900.0;

bool isWide(BuildContext c) => MediaQuery.sizeOf(c).width >= wideBreakpoint;

TextStyle display(double size) => TextStyle(
      fontFamily: 'InterDisplay',
      fontWeight: FontWeight.w800,
      fontSize: size,
      height: 1.1,
      letterSpacing: -0.02 * size,
      color: C.text,
    );

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: C.violet, brightness: Brightness.dark).copyWith(
    primary: C.violet,
    secondary: C.pink,
    surface: C.surface,
    onSurface: C.text,
    error: C.red,
    outline: C.border,
    outlineVariant: C.border,
  );
  final base = ThemeData(useMaterial3: true, brightness: Brightness.dark, fontFamily: 'Inter');
  final text = base.textTheme.apply(bodyColor: C.text, displayColor: C.text);

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodySmall: text.bodySmall?.copyWith(color: C.muted, height: 1.4),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.45),
    ),
    splashFactory: InkRipple.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: C.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w700, color: C.text),
    ),
    dividerTheme: const DividerThemeData(color: C.border, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface2,
      labelStyle: const TextStyle(color: C.muted),
      hintStyle: const TextStyle(color: C.faint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.border)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.border)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.violet, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.violet,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.text,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        side: const BorderSide(color: C.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: C.muted,
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.surface2,
      contentTextStyle: const TextStyle(fontFamily: 'Inter', color: C.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: C.border)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: C.border)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: C.surface2,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      position: PopupMenuPosition.under,
      textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500, color: C.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: C.border)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.surface,
      indicatorColor: C.violet.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      height: 66,
      labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: C.violet, linearTrackColor: C.surface2),
    checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontFamily: 'Inter', color: C.text, fontSize: 12),
    ),
  );
}
