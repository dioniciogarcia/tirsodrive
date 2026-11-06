import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFF0E1320);
  static const panel = Color(0xFF0B101B);
  static const surface = Color(0xFF161D2E);
  static const surface2 = Color(0xFF1A2236);
  static const raised = Color(0xFF2A3654);
  static const border = Color(0xFF232C42);
  static const border2 = Color(0xFF2E3A57);
  static const divider = Color(0xFF1D2539);
  static const text = Color(0xFFE6EAF2);
  static const soft = Color(0xFFB5BED0);
  static const muted = Color(0xFF9AA4B8);
  static const label = Color(0xFF8C97AD);
  static const accent = Color(0xFF3BA7F5);
  static const accentSoft = Color(0xFF7CC4FA);
  static const onAccent = Color(0xFF08111F);
  static const green = Color(0xFF6FD39A);
  static const greenBg = Color(0xFF12261F);
  static const greenBorder = Color(0xFF1E4A38);
  static const amber = Color(0xFFF5A524);
  static const amberBg = Color(0xFF2A1E0C);
  static const amberBorder = Color(0xFF5A3D10);
  static const amberText = Color(0xFFFBD38D);
  static const red = Color(0xFFE86F6F);
}

const String displayFont = 'SpaceGrotesk';

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(
      primary: C.accent,
      onPrimary: C.onAccent,
      secondary: C.accentSoft,
      surface: C.surface,
      onSurface: C.text,
      error: C.red,
    ),
  );
  return base.copyWith(
    dividerColor: C.divider,
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: C.raised,
      contentTextStyle: TextStyle(color: C.text, fontFamily: 'Inter'),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface,
      labelStyle: const TextStyle(color: C.muted),
      hintStyle: const TextStyle(color: C.label),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.border2)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.accent, width: 1.6)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.accent,
        foregroundColor: C.onAccent,
        disabledBackgroundColor: C.raised,
        disabledForegroundColor: C.muted,
        minimumSize: const Size(48, 52),
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.text,
        backgroundColor: C.surface,
        side: const BorderSide(color: C.border2),
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: C.accentSoft, textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: C.border)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: C.surface, showDragHandle: true),
    popupMenuTheme: PopupMenuThemeData(color: C.surface2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: C.accent, linearTrackColor: C.border, circularTrackColor: C.border),
  );
}

/// The blue rounded square with the paper plane.
class TdLogo extends StatelessWidget {
  final double size;
  const TdLogo({super.key, this.size = 34});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.asset('assets/logo.png', width: size, height: size, filterQuality: FilterQuality.medium),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.0, color: C.label),
      );
}

/// Small colored square with the file type, like "Z64" or "APK".
class ExtBadge extends StatelessWidget {
  final String text;
  final Color color;
  final double size;
  const ExtBadge(this.text, {super.key, this.color = C.accent, this.size = 42});
  @override
  Widget build(BuildContext context) {
    final label = text.isEmpty ? '···' : (text.length > 4 ? text.substring(0, 4) : text);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Color.alphaBlend(color.withValues(alpha: 0.22), C.surface), borderRadius: BorderRadius.circular(size * 0.25)),
      child: Text(label,
          style: TextStyle(fontFamily: displayFont, fontWeight: FontWeight.w700, fontSize: size * 0.27, color: Color.lerp(color, Colors.white, 0.45))),
    );
  }
}

class Bar extends StatelessWidget {
  final double value;
  final double height;
  const Bar(this.value, {super.key, this.height = 6});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(value: value <= 0 ? null : value, minHeight: height),
      );
}

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color borderColor;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color = C.surface, this.borderColor = C.border});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor)),
        child: child,
      );
}

class LangSwitch extends StatelessWidget {
  final String lang;
  final ValueChanged<String> onChanged;
  const LangSwitch({super.key, required this.lang, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    Widget b(String code) => Padding(
          padding: const EdgeInsets.all(3),
          child: Material(
            color: lang == code ? C.raised : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onChanged(code),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                child: Text(code.toUpperCase(),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: lang == code ? C.text : C.muted)),
              ),
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(9), border: Border.all(color: C.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [b('en'), b('es')]),
    );
  }
}

void snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}
