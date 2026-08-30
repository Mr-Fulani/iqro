import 'package:flutter/material.dart';

@immutable
class IqroColors extends ThemeExtension<IqroColors> {
  const IqroColors({
    required this.ink,
    required this.inkSoft,
    required this.sand,
    required this.lavender,
    required this.gold,
    required this.panelSoft,
    required this.line,
  });

  final Color ink;
  final Color inkSoft;
  final Color sand;
  final Color lavender;
  final Color gold;
  final Color panelSoft;
  final Color line;

  @override
  IqroColors copyWith({
    Color? ink,
    Color? inkSoft,
    Color? sand,
    Color? lavender,
    Color? gold,
    Color? panelSoft,
    Color? line,
  }) {
    return IqroColors(
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      sand: sand ?? this.sand,
      lavender: lavender ?? this.lavender,
      gold: gold ?? this.gold,
      panelSoft: panelSoft ?? this.panelSoft,
      line: line ?? this.line,
    );
  }

  @override
  IqroColors lerp(covariant IqroColors? other, double t) {
    if (other == null) return this;
    return IqroColors(
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      sand: Color.lerp(sand, other.sand, t)!,
      lavender: Color.lerp(lavender, other.lavender, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      panelSoft: Color.lerp(panelSoft, other.panelSoft, t)!,
      line: Color.lerp(line, other.line, t)!,
    );
  }
}

class IqroTheme {
  static const _emerald = Color(0xFF0B5D4A);
  static const _emeraldDark = Color(0xFF073E34);
  static const _cream = Color(0xFFF7F4EC);

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: _emerald,
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFD9EEE7),
      onPrimaryContainer: Color(0xFF063E33),
      secondary: Color(0xFF9A6D22),
      onSecondary: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFDF8),
      onSurface: Color(0xFF17201D),
      error: Color(0xFFBA1A1A),
      outline: Color(0xFFCBC8BE),
      outlineVariant: Color(0xFFE4E0D6),
    );
    return _base(
      scheme,
      brightness: Brightness.light,
      scaffold: _cream,
      extension: const IqroColors(
        ink: _emeraldDark,
        inkSoft: Color(0xFF1E6657),
        sand: Color(0xFFF5EAD5),
        lavender: Color(0xFFECE8F6),
        gold: Color(0xFFC49647),
        panelSoft: Color(0xFFEFEEE8),
        line: Color(0xFFDCD8CE),
      ),
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: Color(0xFF91D7C3),
      onPrimary: Color(0xFF00382C),
      primaryContainer: Color(0xFF0C5847),
      onPrimaryContainer: Color(0xFFC4F4E4),
      secondary: Color(0xFFE7C27D),
      onSecondary: Color(0xFF402D00),
      surface: Color(0xFF10221D),
      onSurface: Color(0xFFF2F2EA),
      error: Color(0xFFFFB4AB),
      outline: Color(0xFF75847E),
      outlineVariant: Color(0xFF34473F),
    );
    return _base(
      scheme,
      brightness: Brightness.dark,
      scaffold: const Color(0xFF071A16),
      extension: const IqroColors(
        ink: Color(0xFF0A2B24),
        inkSoft: Color(0xFF17483D),
        sand: Color(0xFF332C21),
        lavender: Color(0xFF292735),
        gold: Color(0xFFE2B665),
        panelSoft: Color(0xFF172A24),
        line: Color(0xFF30443D),
      ),
    );
  }

  static ThemeData _base(
    ColorScheme scheme, {
    required Brightness brightness,
    required Color scaffold,
    required IqroColors extension,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      visualDensity: VisualDensity.standard,
    );
    final textTheme = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontFamily: 'serif',
        fontSize: 36,
        fontWeight: FontWeight.w600,
        height: 1.1,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontFamily: 'serif',
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.15,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.45,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
    return base.copyWith(
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[extension],
      dividerColor: extension.line,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: extension.line),
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: extension.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: extension.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: BorderSide(color: extension.line),
          textStyle: textTheme.labelLarge,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: extension.ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

extension IqroThemeContext on BuildContext {
  IqroColors get iqroColors => Theme.of(this).extension<IqroColors>()!;
}
