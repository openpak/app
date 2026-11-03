/// The website's design tokens, so the app and the site are visibly one
/// product. Values hand-copied from `website/web/src/input.css` (the 2026-10
/// "console HOME menu" redesign: a cool shell-grey page, white tiles, slate
/// ink, and a cyan selection cursor that only ever means "where you are") —
/// when that file moves, this one moves with it.
library;

import 'package:flutter/material.dart';

/// The rounded UI face (OFL, assets/fonts): headings, labels, buttons and
/// numbers. Body text stays on the system font, as on the site, so long
/// reading keeps the platform's own rendering.
const uiFont = 'M PLUS Rounded 1c';

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
    required this.cardLine,
    required this.cursor,
    required this.cursor2,
    required this.accent2,
    required this.onAccent,
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
    required this.shadowRaised,
  });

  final Color paper2, raised, sunk, ink2, muted, faint, line, line2, accent2, accentWeak, accentLine;
  final Color ok, okWeak, okLine, warn, warnWeak, warnLine, bad, badWeak, badLine;

  /// The selection cursor and the colour it breathes into. Reserved for
  /// hover, focus and "current": if it is decoration, it stops meaning anything.
  final Color cursor, cursor2;

  /// Text and icons on an accent fill. The accent is light in dark mode, so
  /// white would vanish there; the site uses this near-black indigo instead.
  final Color onAccent;

  /// A card's outline. Dark cards are lifted by their lighter fill alone, so
  /// the site drops the border there; transparent keeps the layout identical.
  final Color cardLine;

  /// The site's --shadow-sm: a card rests on the page, it does not float.
  final List<BoxShadow> shadow;

  /// The site's --shadow: [shadow] plus a soft drop, for a selected tile.
  final List<BoxShadow> shadowRaised;

  static const light = Tokens(
    paper2: Color(0xFFF2F4F7),
    raised: Color(0xFFFFFFFF),
    sunk: Color(0xFFDDE1E7),
    ink2: Color(0xFF48505C),
    muted: Color(0xFF6B7380),
    faint: Color(0xFF9AA1AB),
    line: Color(0xFFD9DDE3),
    line2: Color(0xFFC3C9D1),
    cardLine: Color(0xFFD9DDE3),
    cursor: Color(0xFF0094BE),
    cursor2: Color(0xFF39C9EA),
    accent2: Color(0xFF6366F1),
    onAccent: Color(0xFFFFFFFF),
    accentWeak: Color(0xFFECEEFF),
    accentLine: Color(0xFFC5CAFB),
    ok: Color(0xFF138A45),
    okWeak: Color(0xFFE3F5EA),
    okLine: Color(0xFFB2E0C3),
    warn: Color(0xFFA35F00),
    warnWeak: Color(0xFFFDF2DC),
    warnLine: Color(0xFFEFD39C),
    bad: Color(0xFFC42B2B),
    badWeak: Color(0xFFFDE9E9),
    badLine: Color(0xFFF2BFBF),
    shadow: [BoxShadow(color: Color(0x0F20262F), offset: Offset(0, 1))],
    shadowRaised: [
      BoxShadow(color: Color(0x0F20262F), offset: Offset(0, 1)),
      BoxShadow(color: Color(0x4020262F), offset: Offset(0, 6), blurRadius: 16, spreadRadius: -10),
    ],
  );

  static const dark = Tokens(
    paper2: Color(0xFF2B2F36),
    raised: Color(0xFF31353D),
    sunk: Color(0xFF1D2025),
    ink2: Color(0xFFC4C9D1),
    muted: Color(0xFF949BA6),
    faint: Color(0xFF6C737E),
    line: Color(0xFF3B4048),
    line2: Color(0xFF4A505A),
    cardLine: Color(0x00000000),
    cursor: Color(0xFF3AD7F2),
    cursor2: Color(0xFFA2EFFF),
    accent2: Color(0xFFA5ABFF),
    onAccent: Color(0xFF15172E),
    accentWeak: Color(0xFF2E3156),
    accentLine: Color(0xFF4A4F8C),
    ok: Color(0xFF4FD486),
    okWeak: Color(0xFF1F3A2B),
    okLine: Color(0xFF2F5C42),
    warn: Color(0xFFF6BD4F),
    warnWeak: Color(0xFF3F3320),
    warnLine: Color(0xFF6A5328),
    bad: Color(0xFFFF7676),
    badWeak: Color(0xFF432528),
    badLine: Color(0xFF6E3439),
    shadow: [BoxShadow(color: Color(0x40000000), offset: Offset(0, 1))],
    shadowRaised: [
      BoxShadow(color: Color(0x40000000), offset: Offset(0, 1)),
      BoxShadow(color: Color(0x99000000), offset: Offset(0, 8), blurRadius: 18, spreadRadius: -10),
    ],
  );

  @override
  Tokens copyWith() => this;

  @override
  Tokens lerp(ThemeExtension<Tokens>? other, double t) => this;
}

/// Tile radius (the site's --radius-card is 14); large panels use [radiusLg].
const radiusCard = 14.0;
const radiusLg = 18.0;

/// The selection cursor's rings: a 3px gap in the page's own colour, then a
/// 4px ring. Flutter paints a shadow list first to last, so the wide ring goes
/// down first and the gap over it.
List<BoxShadow> cursorShadows(Color gap, Color ring) => [
  BoxShadow(color: ring, spreadRadius: 7),
  BoxShadow(color: gap, spreadRadius: 3),
];

/// Read the palette without threading it through every widget.
Tokens tokensOf(BuildContext context) => Theme.of(context).extension<Tokens>()!;

const _accentLight = Color(0xFF4F46E5); // --accent
const _accentDark = Color(0xFF9198FF);
const _paperLight = Color(0xFFE9ECF0);
const _paperDark = Color(0xFF24272D);
const _inkLight = Color(0xFF20262F);
const _inkDark = Color(0xFFEEF1F5);

ThemeData _base(Brightness b, Color accent, Color paper, Color ink, Tokens t) {
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: b).copyWith(
    primary: accent,
    onPrimary: t.onAccent,
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
  final pillText = const TextStyle(fontFamily: uiFont, fontWeight: FontWeight.w700, fontSize: 15);
  OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: c, width: w),
  );
  // Hover and keyboard focus select a button the way they select a tile: the
  // cursor colour on its edge. (The full breathing ring is for tiles; a button
  // is small enough that a 2px edge reads as the same cursor.)
  WidgetStateProperty<BorderSide?> selectedEdge(BorderSide rest) => WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.focused) || s.contains(WidgetState.hovered)
        ? BorderSide(color: t.cursor, width: 2)
        : rest,
  );
  final base = ThemeData(useMaterial3: true, brightness: b, colorScheme: scheme);
  final tt = base.textTheme;
  // Headings are UI, so they speak in the rounded face. Rounded letters want
  // air, not the tight negative tracking a grotesk takes.
  TextStyle? ui(TextStyle? s, FontWeight w) => s?.copyWith(fontFamily: uiFont, fontWeight: w, letterSpacing: 0);
  final text = tt.copyWith(
    displayLarge: ui(tt.displayLarge, FontWeight.w800),
    displayMedium: ui(tt.displayMedium, FontWeight.w800),
    displaySmall: ui(tt.displaySmall, FontWeight.w800),
    headlineLarge: ui(tt.headlineLarge, FontWeight.w800),
    headlineMedium: ui(tt.headlineMedium, FontWeight.w800),
    headlineSmall: ui(tt.headlineSmall, FontWeight.w800),
    titleLarge: ui(tt.titleLarge, FontWeight.w800),
    titleMedium: ui(tt.titleMedium, FontWeight.w700),
    titleSmall: ui(tt.titleSmall, FontWeight.w700),
    labelLarge: ui(tt.labelLarge, FontWeight.w700),
    labelMedium: ui(tt.labelMedium, FontWeight.w700),
    labelSmall: ui(tt.labelSmall, FontWeight.w700),
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
        side: BorderSide(color: t.cardLine),
      ),
    ),
    // The site's glass header: the page tint, a hairline under it.
    appBarTheme: AppBarTheme(
      backgroundColor: paper.withValues(alpha: 0.9),
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: uiFont, color: ink, fontSize: 22, fontWeight: FontWeight.w800),
      shape: Border(bottom: BorderSide(color: t.line)),
    ),
    // A well sunk into the tile, and the cursor when it has focus.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.paper2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: field(t.line2),
      enabledBorder: field(t.line2),
      focusedBorder: field(t.cursor, 2),
      prefixIconColor: t.muted,
      hintStyle: TextStyle(color: t.faint),
    ),
    // Every button is a pill. Primary is flat accent (the site dropped the
    // gradient), lighter on hover, with the cursor on its edge when selected.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: pill,
        textStyle: pillText,
        foregroundColor: t.onAccent,
        backgroundColor: accent,
        disabledBackgroundColor: t.paper2,
        padding: const EdgeInsets.symmetric(horizontal: 20),
      ).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? t.paper2
              : s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
              ? t.accent2
              : accent,
        ),
        side: selectedEdge(BorderSide.none),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 44),
        shape: pill,
        textStyle: pillText,
        foregroundColor: ink,
        backgroundColor: t.raised,
      ).copyWith(side: selectedEdge(BorderSide(color: t.line2))),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: pill, textStyle: pillText, foregroundColor: accent)
          .copyWith(side: selectedEdge(BorderSide.none)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: t.sunk,
        selectedBackgroundColor: t.raised,
        selectedForegroundColor: ink,
        foregroundColor: t.muted,
        side: BorderSide(color: t.line),
        shape: pill,
        textStyle: const TextStyle(fontFamily: uiFont, fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: StadiumBorder(side: BorderSide(color: t.line)),
      backgroundColor: t.raised,
      selectedColor: ink,
      labelStyle: TextStyle(fontFamily: uiFont, color: ink, fontWeight: FontWeight.w700),
      secondaryLabelStyle: TextStyle(fontFamily: uiFont, color: paper, fontWeight: FontWeight.w700),
      checkmarkColor: paper,
      showCheckmark: false,
    ),
    dialogTheme: DialogThemeData(
      // The Material default (headlineSmall, 24 sp at w800 here) wraps short titles such as
      // "Downloading the update…" onto two lines on a phone.
      titleTextStyle: TextStyle(fontFamily: uiFont, color: ink, fontSize: 18, fontWeight: FontWeight.w800, height: 1.25),
      backgroundColor: t.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
        side: BorderSide(color: t.cardLine),
      ),
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
    // The phone menu is HOME's row of round system buttons: every destination
    // sits in a round well ([NavWell]), and the current one wears the cursor.
    // The indicator pill is gone; the ring says where you are.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: paper.withValues(alpha: 0.94),
      indicatorColor: Colors.transparent,
      elevation: 0,
      height: 76,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: uiFont,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: s.contains(WidgetState.selected) ? ink : t.muted,
        ),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.line, space: 1, thickness: 1),
  );
}

/// The tokens a Rewards theme may set (openpak-theme/1), named like the
/// website's custom properties. The selection cursor is not one: it stays.
const themeTokenNames = {
  'paper', 'paper-2', 'raised', 'sunk', 'ink', 'ink-2', 'muted', 'faint', 'line', 'line-2',
  'accent', 'accent-2', 'accent-weak', 'accent-line', 'on-accent',
  'ok', 'ok-weak', 'ok-line', 'bad', 'bad-weak', 'bad-line', 'warn', 'warn-weak', 'warn-line',
};

/// A theme must carry these in both modes to be used at all (as on the site).
const themeRequiredTokens = ['paper', 'ink', 'accent', 'on-accent'];

// The same strict grammar the website checks: hex (#rgb #rgba #rrggbb
// #rrggbbaa) or rgb()/rgba() with comma-separated numbers, nothing else.
final _hexColour = RegExp(r'^#([0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$', caseSensitive: false);
const _byte = r'(25[0-5]|2[0-4]\d|1?\d?\d)';
final _rgbColour = RegExp(
  r'^rgba?\(\s*' + _byte + r'\s*,\s*' + _byte + r'\s*,\s*' + _byte + r'\s*(?:,\s*(0|1|0?\.\d{1,4}|1\.0{1,4})\s*)?\)$',
  caseSensitive: false,
);

/// A colour from a theme token, or null for anything that is not a strict
/// colour. Hex alpha is last (CSS), not first (Flutter).
Color? parseThemeColor(String? raw) {
  final v = raw?.trim();
  if (v == null || v.isEmpty || v.length > 40) return null;
  if (_hexColour.hasMatch(v)) {
    var h = v.substring(1);
    if (h.length <= 4) h = h.split('').map((c) => '$c$c').join();
    final n = int.parse(h, radix: 16);
    return h.length == 6 ? Color(0xFF000000 | n) : Color(((n & 0xFF) << 24) | (n >> 8));
  }
  final m = _rgbColour.firstMatch(v);
  if (m == null) return null;
  final a = m.group(4) == null ? 1.0 : double.parse(m.group(4)!);
  return Color.fromRGBO(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!), a);
}

/// Only the known tokens whose value is a strict colour.
Map<String, Color> validThemeTokens(Map<String, String>? raw) => {
  if (raw != null)
    for (final e in raw.entries)
      if (themeTokenNames.contains(e.key))
        if (parseThemeColor(e.value) case final c?) e.key: c,
};

/// Whether a theme's two modes both carry the required tokens as valid
/// colours; anything else is shown as the default look.
bool themeUsable(Map<String, String> light, Map<String, String> dark) {
  final l = validThemeTokens(light), d = validThemeTokens(dark);
  return themeRequiredTokens.every((k) => l.containsKey(k) && d.containsKey(k));
}

/// Tokens for a mode: the theme's valid values, the default for every token
/// it leaves out or gets wrong. The selection cursor is always the default.
Tokens tokensFromTheme(Brightness b, Map<String, String>? raw) {
  final d = b == Brightness.dark ? Tokens.dark : Tokens.light;
  final c = validThemeTokens(raw);
  return Tokens(
    paper2: c['paper-2'] ?? d.paper2,
    raised: c['raised'] ?? d.raised,
    sunk: c['sunk'] ?? d.sunk,
    ink2: c['ink-2'] ?? d.ink2,
    muted: c['muted'] ?? d.muted,
    faint: c['faint'] ?? d.faint,
    line: c['line'] ?? d.line,
    line2: c['line-2'] ?? d.line2,
    cardLine: b == Brightness.dark ? d.cardLine : (c['line'] ?? d.cardLine),
    cursor: d.cursor,
    cursor2: d.cursor2,
    accent2: c['accent-2'] ?? d.accent2,
    onAccent: c['on-accent'] ?? d.onAccent,
    accentWeak: c['accent-weak'] ?? d.accentWeak,
    accentLine: c['accent-line'] ?? d.accentLine,
    ok: c['ok'] ?? d.ok,
    okWeak: c['ok-weak'] ?? d.okWeak,
    okLine: c['ok-line'] ?? d.okLine,
    warn: c['warn'] ?? d.warn,
    warnWeak: c['warn-weak'] ?? d.warnWeak,
    warnLine: c['warn-line'] ?? d.warnLine,
    bad: c['bad'] ?? d.bad,
    badWeak: c['bad-weak'] ?? d.badWeak,
    badLine: c['bad-line'] ?? d.badLine,
    shadow: d.shadow,
    shadowRaised: d.shadowRaised,
  );
}

/// The app's ThemeData for a mode, optionally re-coloured by a Rewards
/// theme's tokens (see [tokensFromTheme]). No tokens: the default look.
ThemeData openPakTheme(Brightness b, [Map<String, String>? raw]) {
  final dark = b == Brightness.dark;
  final c = validThemeTokens(raw);
  return _base(
    b,
    c['accent'] ?? (dark ? _accentDark : _accentLight),
    c['paper'] ?? (dark ? _paperDark : _paperLight),
    c['ink'] ?? (dark ? _inkDark : _inkLight),
    tokensFromTheme(b, raw),
  );
}

ThemeData openPakLight([Map<String, String>? tokens]) => openPakTheme(Brightness.light, tokens);
ThemeData openPakDark([Map<String, String>? tokens]) => openPakTheme(Brightness.dark, tokens);
