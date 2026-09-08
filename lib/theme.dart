/// The website's design tokens, so the app and the site are visibly one
/// product. Values copied from `website/web/static/site.css` — when that file
/// moves, this one moves with it.
library;

import 'package:flutter/material.dart';

class Tokens extends ThemeExtension<Tokens> {
  const Tokens({
    required this.paper2,
    required this.raised,
    required this.ink2,
    required this.muted,
    required this.line,
    required this.line2,
    required this.accentWeak,
    required this.ok,
    required this.okWeak,
    required this.okLine,
    required this.warn,
    required this.warnWeak,
    required this.warnLine,
    required this.bad,
    required this.badWeak,
    required this.badLine,
  });

  final Color paper2, raised, ink2, muted, line, line2, accentWeak;
  final Color ok, okWeak, okLine, warn, warnWeak, warnLine, bad, badWeak, badLine;

  static const light = Tokens(
    paper2: Color(0xFFF7F7F8),
    raised: Color(0xFFFFFFFF),
    ink2: Color(0xFF3D3F47),
    muted: Color(0xFF6B6E79),
    line: Color(0xFFE4E4E8),
    line2: Color(0xFFC9CAD1),
    accentWeak: Color(0xFFEEF0FF),
    ok: Color(0xFF1A7F4B),
    okWeak: Color(0xFFE8F5EE),
    okLine: Color(0xFFBFE0CD),
    warn: Color(0xFF8A5A00),
    warnWeak: Color(0xFFFDF4E3),
    warnLine: Color(0xFFEDDCB4),
    bad: Color(0xFFB3261E),
    badWeak: Color(0xFFFBECEB),
    badLine: Color(0xFFEEC4C1),
  );

  static const dark = Tokens(
    paper2: Color(0xFF191A1F),
    raised: Color(0xFF1C1E24),
    ink2: Color(0xFFB7BAC2),
    muted: Color(0xFF8A8E99),
    line: Color(0xFF26282E),
    line2: Color(0xFF3B3E47),
    accentWeak: Color(0xFF1C2040),
    ok: Color(0xFF4EC98A),
    okWeak: Color(0xFF12251B),
    okLine: Color(0xFF2C4D3A),
    warn: Color(0xFFE5B169),
    warnWeak: Color(0xFF241C10),
    warnLine: Color(0xFF4D3D24),
    bad: Color(0xFFFF8079),
    badWeak: Color(0xFF2A1615),
    badLine: Color(0xFF57302C),
  );

  @override
  Tokens copyWith() => this;

  @override
  Tokens lerp(ThemeExtension<Tokens>? other, double t) => this;
}

/// Read the palette without threading it through every widget.
Tokens tokensOf(BuildContext context) => Theme.of(context).extension<Tokens>()!;

const _accentLight = Color(0xFF4F46E5); // --accent
const _accentDark = Color(0xFF818CF8);
const _paperLight = Color(0xFFFFFFFF);
const _paperDark = Color(0xFF101114);
const _inkLight = Color(0xFF16161A);
const _inkDark = Color(0xFFE9EAEE);

ThemeData _base(Brightness b, Color accent, Color paper, Color ink, Tokens t) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: accent,
        brightness: b,
      ).copyWith(
        primary: accent,
        surface: paper,
        onSurface: ink,
        error: t.bad,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    extensions: [t],
    // The site's 12px radius, its hairline borders and its flat surfaces:
    // cards that sit on the page rather than hover over it.
    cardTheme: CardThemeData(
      color: t.raised,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: t.line),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: t.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.paper2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: t.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: t.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.raised,
      indicatorColor: t.accentWeak,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(color: t.line, space: 1, thickness: 1),
  );
}

ThemeData openPakLight() =>
    _base(Brightness.light, _accentLight, _paperLight, _inkLight, Tokens.light);
ThemeData openPakDark() =>
    _base(Brightness.dark, _accentDark, _paperDark, _inkDark, Tokens.dark);
