import 'package:flutter/material.dart';
import '../core/strings.dart';

class C {
  /// true = dark colors. Set from Settings (Light / Dark / Automatic).
  static bool dark = true;
  static Color get bg => dark ? const Color(0xFF0E1320) : const Color(0xFFF4F6FA);
  static Color get panel => dark ? const Color(0xFF0B101B) : const Color(0xFFFFFFFF);
  static Color get surface => dark ? const Color(0xFF161D2E) : const Color(0xFFFFFFFF);
  static Color get surface2 => dark ? const Color(0xFF1A2236) : const Color(0xFFEEF2F8);
  static Color get raised => dark ? const Color(0xFF2A3654) : const Color(0xFFDCE6F5);
  static Color get border => dark ? const Color(0xFF232C42) : const Color(0xFFE0E6EF);
  static Color get border2 => dark ? const Color(0xFF2E3A57) : const Color(0xFFCBD4E1);
  static Color get divider => dark ? const Color(0xFF1D2539) : const Color(0xFFE6EAF1);
  static Color get text => dark ? const Color(0xFFE6EAF2) : const Color(0xFF111827);
  static Color get soft => dark ? const Color(0xFFB5BED0) : const Color(0xFF374151);
  static Color get muted => dark ? const Color(0xFF9AA4B8) : const Color(0xFF5B6577);
  static Color get label => dark ? const Color(0xFF8C97AD) : const Color(0xFF697386);
  static Color get accent => dark ? const Color(0xFF3BA7F5) : const Color(0xFF1683D6);
  static Color get accentSoft => dark ? const Color(0xFF7CC4FA) : const Color(0xFF0F6CB3);
  static Color get onAccent => dark ? const Color(0xFF08111F) : const Color(0xFFFFFFFF);
  static Color get green => dark ? const Color(0xFF6FD39A) : const Color(0xFF1C8F52);
  static Color get greenBg => dark ? const Color(0xFF12261F) : const Color(0xFFE7F6EE);
  static Color get greenBorder => dark ? const Color(0xFF1E4A38) : const Color(0xFFBCE3CC);
  static Color get greenSub => dark ? const Color(0xFFA9C9B8) : const Color(0xFF2F6B4B);
  static Color get amber => dark ? const Color(0xFFF5A524) : const Color(0xFFF5A524);
  static Color get amberBg => dark ? const Color(0xFF2A1E0C) : const Color(0xFFFFF6E3);
  static Color get amberBorder => dark ? const Color(0xFF5A3D10) : const Color(0xFFF0D39B);
  static Color get amberText => dark ? const Color(0xFFFBD38D) : const Color(0xFF8A5A00);
  static Color get amberSub => dark ? const Color(0xFFF1DDBA) : const Color(0xFF6B4A12);
  static Color get amberTip => dark ? const Color(0xFFD9BE8E) : const Color(0xFF7A5A1F);
  static Color get red => dark ? const Color(0xFFE86F6F) : const Color(0xFFC93C3C);
  static Color get selected => dark ? const Color(0xFF1E2A44) : const Color(0xFFDCEBFB);
  static Color get strong => dark ? const Color(0xFFFFFFFF) : const Color(0xFF0B1220);
}

const String displayFont = 'SpaceGrotesk';

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: C.dark ? Brightness.dark : Brightness.light,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: C.bg,
    colorScheme: (C.dark ? ColorScheme.dark() : ColorScheme.light()).copyWith(
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
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.raised,
      contentTextStyle: TextStyle(color: C.text, fontFamily: 'Inter'),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface,
      labelStyle: TextStyle(color: C.muted),
      hintStyle: TextStyle(color: C.label),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: C.border2)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: C.accent, width: 1.6)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.accent,
        foregroundColor: C.onAccent,
        disabledBackgroundColor: C.raised,
        disabledForegroundColor: C.muted,
        minimumSize: Size(48, 52),
        textStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.text,
        backgroundColor: C.surface,
        side: BorderSide(color: C.border2),
        minimumSize: Size(44, 44),
        textStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: C.accentSoft, textStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: C.border)),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: C.surface, showDragHandle: true),
    popupMenuTheme: PopupMenuThemeData(color: C.surface2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: C.accent, linearTrackColor: C.border, circularTrackColor: C.border),
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
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.0, color: C.label),
      );
}

/// Small colored square with the file type, like "Z64" or "APK".
class ExtBadge extends StatelessWidget {
  final String text;
  final Color? color;
  final double size;
  const ExtBadge(this.text, {super.key, this.color, this.size = 42});
  @override
  Widget build(BuildContext context) {
    final color = this.color ?? C.accent;
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
  final Color? color;
  final Color? borderColor;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.borderColor});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: color ?? C.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor ?? C.border)),
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
          padding: EdgeInsets.all(3),
          child: Material(
            color: lang == code ? C.raised : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onChanged(code),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 11, vertical: 7),
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


/// Small connection indicator: green dot = connected, amber = waiting for network,
/// spinner ONLY while really connecting. TDLib's "updating" (catching up on messages) counts as connected.
class ConnectionDot extends StatelessWidget {
  final String state;
  const ConnectionDot({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final connecting = state == 'connectionStateConnecting' || state == 'connectionStateConnectingToProxy';
    final waiting = state == 'connectionStateWaitingForNetwork';
    final label = connecting ? t('status_connecting') : (waiting ? t('status_waiting') : t('status_online'));
    return Tooltip(
      message: label,
      child: SizedBox(
        width: 16,
        height: 16,
        child: Center(
          child: connecting
              ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
              : Container(width: 10, height: 10, decoration: BoxDecoration(color: waiting ? C.amber : C.green, shape: BoxShape.circle)),
        ),
      ),
    );
  }
}
