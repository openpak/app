import 'package:flutter/material.dart';
import 'package:openpak/l10n.dart';

/// A MaterialApp with the app's localizations, English unless [locale] says
/// otherwise, so a screen under test reads its strings as it does in the app.
MaterialApp localizedApp({required Widget home, ThemeData? theme, Locale locale = const Locale('en')}) =>
    MaterialApp(
      theme: theme,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );
