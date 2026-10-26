import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Shared locale for every application/engine, including native subwindows.
abstract final class AppLocalization {
  static const locale = Locale('zh', 'CN');
  static const supportedLocales = [locale];
  static const delegates = <LocalizationsDelegate<dynamic>>[
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
}
