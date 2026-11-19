import 'package:flutter/material.dart';

/// Design tokens mirrored from OpenSEO's daisyUI theme.
/// Light: white surfaces on a near-white canvas with a muted blue primary.
/// Dark: near-black canvas with a lifted content panel.
class _Palette {
  const _Palette({
    required this.base100,
    required this.base200,
    required this.base300,
    required this.content,
    required this.primary,
    required this.secondary,
    required this.neutral,
  });

  final Color base100, base200, base300, content, primary, secondary, neutral;
  Color get onPrimary => const Color(0xFFFFFFFF);
  Color get onSecondary => const Color(0xFFFFFFFF);
  Color get error => const Color(0xFFF14D4C);
}

const _light = _Palette(
  base100: Color(0xFFFFFFFF),
  base200: Color(0xFFF5F5F5),
  base300: Color(0xFFE4E4E4),
  content: Color(0xFF161616),
  primary: Color(0xFF3C61A7),
  secondary: Color(0xFF278733),
  neutral: Color(0xFF222222),
);

const _dark = _Palette(
  base100: Color(0xFF121212),
  base200: Color(0xFF060606),
  base300: Color(0xFF262626),
  content: Color(0xFFE4E4E4),
  primary: Color(0xFF6991DC),
  secondary: Color(0xFF3A9742),
  neutral: Color(0xFFCECECE),
);

TextTheme _textTheme(Color content) {
  final muted = content.withValues(alpha: 0.72);
  TextStyle style(
    double size, {
    double? height,
    FontWeight? weight,
    Color? color,
  }) => TextStyle(
    fontSize: size,
    height: height,
    fontWeight: weight,
    color: color ?? content,
  );
  return TextTheme(
    headlineMedium: style(28, height: 1.25, weight: FontWeight.w800),
    headlineSmall: style(22, height: 1.3, weight: FontWeight.w800),
    titleLarge: style(20, height: 1.35, weight: FontWeight.w700),
    titleMedium: style(16, height: 1.4, weight: FontWeight.w600),
    titleSmall: style(14, height: 1.45, weight: FontWeight.w600),
    bodyLarge: style(14, height: 1.55),
    bodyMedium: style(14, height: 1.55),
    bodySmall: style(12, height: 1.5, color: muted),
    labelLarge: style(14, weight: FontWeight.w600),
    labelMedium: style(12, weight: FontWeight.w600, color: muted),
    labelSmall: style(11, weight: FontWeight.w500, color: muted),
  );
}

OutlineInputBorder _inputBorder(Color color, [double width = 1]) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: color, width: width),
    );

WidgetStateProperty<T> _onState<T>(WidgetState state, T active, T inactive) =>
    WidgetStateProperty.resolveWith(
      (states) => states.contains(state) ? active : inactive,
    );

ThemeData buildAppTheme(Brightness brightness) {
  final p = brightness == Brightness.light ? _light : _dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: p.primary,
        brightness: brightness,
      ).copyWith(
        primary: p.primary,
        onPrimary: p.onPrimary,
        secondary: p.secondary,
        onSecondary: p.onSecondary,
        error: p.error,
        onError: Colors.white,
        surface: p.base100,
        onSurface: p.content,
        surfaceContainerLowest: p.base100,
        surfaceContainerLow: p.base200,
        surfaceContainer: p.base200,
        surfaceContainerHigh: p.base300,
        surfaceContainerHighest: p.base300,
        outline: p.base300,
        outlineVariant: p.base300.withValues(alpha: 0.6),
        onSurfaceVariant: p.content.withValues(alpha: 0.6),
        inverseSurface: p.neutral,
        onInverseSurface: p.base100,
      );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.base200,
    canvasColor: p.base100,
    dividerColor: p.base300,
  );

  return base.copyWith(
    textTheme: _textTheme(p.content),
    primaryTextTheme: _textTheme(p.base100),
    iconTheme: IconThemeData(color: p.content.withValues(alpha: 0.7), size: 20),
    appBarTheme: AppBarTheme(
      backgroundColor: p.base100,
      foregroundColor: p.content,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 16,
      toolbarHeight: 56,
      iconTheme: IconThemeData(color: p.content, size: 20),
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: p.content,
      ),
      shape: Border(bottom: BorderSide(color: p.base300)),
    ),
    cardTheme: CardThemeData(
      color: p.base100,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    dividerTheme: DividerThemeData(color: p.base300, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.base100,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      labelStyle: TextStyle(
        fontSize: 13,
        color: p.content.withValues(alpha: 0.72),
      ),
      floatingLabelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: p.primary,
      ),
      hintStyle: TextStyle(
        fontSize: 14,
        color: p.content.withValues(alpha: 0.62),
      ),
      errorStyle: TextStyle(fontSize: 12, color: p.error),
      border: _inputBorder(p.content.withValues(alpha: 0.5)),
      enabledBorder: _inputBorder(p.content.withValues(alpha: 0.5)),
      focusedBorder: _inputBorder(p.primary, 1.5),
      errorBorder: _inputBorder(p.error),
      focusedErrorBorder: _inputBorder(p.error, 1.5),
      disabledBorder: _inputBorder(p.base300.withValues(alpha: 0.6)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: _onState(
          WidgetState.disabled,
          p.content.withValues(alpha: 0.12),
          p.primary,
        ),
        foregroundColor: _onState(
          WidgetState.disabled,
          p.content.withValues(alpha: 0.38),
          p.onPrimary,
        ),
        overlayColor: WidgetStatePropertyAll(
          Colors.white.withValues(alpha: 0.08),
        ),
        elevation: const WidgetStatePropertyAll(0),
        minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(p.base100),
        foregroundColor: _onState(
          WidgetState.disabled,
          p.content.withValues(alpha: 0.38),
          p.content,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: p.base300)),
        overlayColor: WidgetStatePropertyAll(p.content.withValues(alpha: 0.04)),
        elevation: const WidgetStatePropertyAll(0),
        minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(p.primary),
        overlayColor: WidgetStatePropertyAll(p.primary.withValues(alpha: 0.06)),
        minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(
          p.content.withValues(alpha: 0.7),
        ),
        overlayColor: WidgetStatePropertyAll(p.content.withValues(alpha: 0.05)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.base100,
      selectedColor: p.base300.withValues(alpha: 0.7),
      disabledColor: p.base200,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: p.content,
      ),
      secondaryLabelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: p.content,
      ),
      side: BorderSide(color: p.base300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      showCheckmark: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.base100,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.primary.withValues(alpha: 0.16),
      indicatorShape: const StadiumBorder(),
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? p.primary
              : p.content.withValues(alpha: 0.6),
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? p.primary
              : p.content.withValues(alpha: 0.6),
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.content.withValues(alpha: 0.6),
      textColor: p.content,
      titleTextStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: p.content,
      ),
      subtitleTextStyle: TextStyle(
        fontSize: 13,
        height: 1.4,
        color: p.content.withValues(alpha: 0.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minVerticalPadding: 10,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.neutral,
      contentTextStyle: TextStyle(color: p.base100, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      elevation: 4,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.base100,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: p.base300),
      ),
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: p.content,
      ),
      contentTextStyle: TextStyle(
        fontSize: 14,
        height: 1.5,
        color: p.content.withValues(alpha: 0.75),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: _onState(
        WidgetState.selected,
        p.onPrimary,
        p.content.withValues(alpha: 0.7),
      ),
      trackColor: _onState(WidgetState.selected, p.primary, p.base300),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.neutral,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(fontSize: 12, color: p.base100),
      waitDuration: const Duration(milliseconds: 400),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.primary,
      selectionColor: p.primary.withValues(alpha: 0.2),
      selectionHandleColor: p.primary,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.primary,
      linearTrackColor: p.base300,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(p.content.withValues(alpha: 0.2)),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(6),
    ),
    splashColor: p.content.withValues(alpha: 0.04),
    highlightColor: p.content.withValues(alpha: 0.03),
  );
}
