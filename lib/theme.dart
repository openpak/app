/// The website's design tokens, so the app and the site are visibly one
/// product. Values copied from `website/web/src/input.css` (v0.54.0 redesign) — when that file
/// moves, this one moves with it.
library;

import 'package:flutter/material.dart';

class Tokens extends ThemeExtension<Tokens> {
  const Tokens({
    required this.paper2,
    required this.raised,
    required this.sunk,
    required this.ink2,
    required this.muted,
    required this.faint,
    required this.line,
    required this.line2,
    required this.accentWeak,
    required this.accentLine,
    required this.ok,
    required this.okWeak,
    required this.okLine,
    required this.warn,
    required this.warnWeak,
    required this.warnLine,
    required this.bad,
    required this.badWeak,
    required this.badLine,
    required this.shadow,
  });

  final Color paper2, raised, sunk, ink2, muted, faint, line, line2, accentWeak, accentLine;
  final Color ok, okWeak, okLine, warn, warnWeak, warnLine, bad, badWeak, badLine;

  /// The site's --shadow-sm: a card rests on the page, it does not float.
  final List<BoxShadow> shadow;

  static const light = Tokens(
    paper2: Color(0xFFF1F1F4),
    raised: Color(0xFFFFFFFF),
    sunk: Color(0xFFEBEBEF),
    ink2: Color(0xFF41444F),
    muted: Color(0xFF6E717D),
    faint: Color(0xFF9A9DA8),
    line: Color(0xFFE5E5EA),
    line2: Color(0xFFD3D4DB),
    accentWeak: Color(0xFFEEF0FF),
    accentLine: Color(0xFFC7CCFB),
    ok: Color(0xFF15803D),
    okWeak: Color(0xFFE7F6EC),
    okLine: Color(0xFFB9E3C6),
    warn: Color(0xFFA16207),
    warnWeak: Color(0xFFFDF5E1),
    warnLine: Color(0xFFF0DCA6),
    bad: Color(0xFFB91C1C),
    badWeak: Color(0xFFFDECEC),
    badLine: Color(0xFFF3C2C2),
    shadow: [BoxShadow(color: Color(0x0D0F1014), offset: Offset(0, 1), blurRadius: 2)],
  );

  static const dark = Tokens(
    paper2: Color(0xFF181A21),
    raised: Color(0xFF121319),
    sunk: Color(0xFF0E0F14),
    ink2: Color(0xFFB4B8C3),
    muted: Color(0xFF858A97),
    faint: Color(0xFF5C606C),
    line: Color(0xFF22242D),
    line2: Color(0xFF2F323D),
    accentWeak: Color(0xFF1A1D3A),
    accentLine: Color(0xFF333A73),
    ok: Color(0xFF4ADE80),
    okWeak: Color(0xFF0F2418),
    okLine: Color(0xFF1F4A2F),
    warn: Color(0xFFFBBF24),
    warnWeak: Color(0xFF261D0B),
    warnLine: Color(0xFF4D3A14),
    bad: Color(0xFFF87171),
    badWeak: Color(0xFF2A1213),
    badLine: Color(0xFF572526),
    shadow: [BoxShadow(color: Color(0x4D000000), offset: Offset(0, 1), blurRadius: 2)],
  );

  @override
  Tokens copyWith() => this;

  @override
  Tokens lerp(ThemeExtension<Tokens>? other, double t) => this;
}

/// Card and row radius (--radius-card); large panels use [radiusLg].
const radiusCard = 16.0;
const radiusLg = 20.0;

/// The primary button's fill: --accent-2 into indigo-700, as on the site.
const primaryGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF6366F1), Color(0xFF4338CA)],
);

/// A blank avatar: the site's pink-to-violet, so an initial still looks chosen.
const avatarGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFF472B6), Color(0xFF8B5CF6)],
);

/// The profile card's cover: indigo into night, pink light in one corner.
const coverGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF4338CA), Color(0xFF6D4BD8), Color(0xFFEC4899)],
  stops: [0, 0.55, 1],
);

/// Read the palette without threading it through every widget.
Tokens tokensOf(BuildContext context) => Theme.of(context).extension<Tokens>()!;

const _accentLight = Color(0xFF4F46E5); // --accent
const _accentDark = Color(0xFF818CF8);
const _paperLight = Color(0xFFF6F6F8);
const _paperDark = Color(0xFF0A0B0F);
const _inkLight = Color(0xFF0E0F14);
const _inkDark = Color(0xFFECEEF3);

ThemeData _base(Brightness b, Color accent, Color paper, Color ink, Tokens t) {
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: b).copyWith(
    primary: accent,
    surface: paper,
    onSurface: ink,
    onSurfaceVariant: t.ink2,
    surfaceContainerLowest: t.raised,
    surfaceContainerLow: t.raised,
    surfaceContainer: t.raised,
    surfaceContainerHigh: t.raised,
    surfaceContainerHighest: t.paper2,
    outline: t.line2,
    outlineVariant: t.line,
    error: t.bad,
  );
  const pill = StadiumBorder();
  final pillText = const TextStyle(fontWeight: FontWeight.w600, fontSize: 15);
  OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: c, width: w),
  );
  final base = ThemeData(useMaterial3: true, brightness: b, colorScheme: scheme);
  // Headings as on the site: heavy and tightly tracked.
  final text = base.textTheme.copyWith(
    headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.9),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.7),
    titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
    titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
  ).apply(bodyColor: ink, displayColor: ink);
  return base.copyWith(
    scaffoldBackgroundColor: paper,
    textTheme: text,
    extensions: [t],
    cardTheme: CardThemeData(
      color: t.raised,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusCard),
        side: BorderSide(color: t.line),
      ),
    ),
    // The site's glass header: the page tint, a hairline under it.
    appBarTheme: AppBarTheme(
      backgroundColor: paper.withValues(alpha: 0.9),
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: ink, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.6),
      shape: Border(bottom: BorderSide(color: t.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: paper,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: field(t.line2),
      enabledBorder: field(t.line2),
      focusedBorder: field(accent, 1.5),
      prefixIconColor: t.muted,
      hintStyle: TextStyle(color: t.faint),
    ),
    // Every button is a pill. Primary is the site's indigo gradient, and a
    // gradient needs backgroundBuilder: backgroundColor only takes a colour.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: pill,
        textStyle: pillText,
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        disabledBackgroundColor: t.paper2,
        padding: const EdgeInsets.symmetric(horizontal: 20),
      ).copyWith(
        backgroundBuilder: (context, states, child) => states.contains(WidgetState.disabled)
            ? child!
            : DecoratedBox(
                decoration: const ShapeDecoration(
                  shape: pill,
                  gradient: primaryGradient,
                  shadows: [BoxShadow(color: Color(0x994F46E5), offset: Offset(0, 6), blurRadius: 16, spreadRadius: -6)],
                ),
                child: child,
              ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 44),
        shape: pill,
        textStyle: pillText,
        foregroundColor: ink,
        backgroundColor: t.raised,
        side: BorderSide(color: t.line2),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: pill, textStyle: pillText, foregroundColor: accent),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: t.sunk,
        selectedBackgroundColor: t.raised,
        selectedForegroundColor: ink,
        foregroundColor: t.muted,
        side: BorderSide(color: t.line),
        shape: pill,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: StadiumBorder(side: BorderSide(color: t.line)),
      backgroundColor: t.raised,
      selectedColor: ink,
      labelStyle: TextStyle(color: ink, fontWeight: FontWeight.w600),
      secondaryLabelStyle: TextStyle(color: paper, fontWeight: FontWeight.w600),
      checkmarkColor: paper,
      showCheckmark: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg), side: BorderSide(color: t.line)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.raised,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard)),
    ),
    listTileTheme: ListTileThemeData(iconColor: t.ink2),
    // The site's tab bar: glass, a hairline on top, the active tab in accent
    // with no pill behind it.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: paper.withValues(alpha: 0.9),
      indicatorColor: Colors.transparent,
      elevation: 0,
      height: 64,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected) ? accent : t.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(size: 24, color: s.contains(WidgetState.selected) ? accent : t.muted),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.line, space: 1, thickness: 1),
  );
}

ThemeData openPakLight() =>
    _base(Brightness.light, _accentLight, _paperLight, _inkLight, Tokens.light);
ThemeData openPakDark() =>
    _base(Brightness.dark, _accentDark, _paperDark, _inkDark, Tokens.dark);
