import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/browser/app_webview_page.dart';

void main() {
  group('parseCssColor tests', () {
    test('parses 6-digit hex correctly', () {
      final color = parseCssColor('#121212');
      expect(color, isNotNull);
      expect(color, const Color(0xFF121212));
      expect(color!.computeLuminance() < 0.5, isTrue, reason: '#121212 should be dark');
    });

    test('parses GitHub dark 6-digit hex correctly', () {
      final color = parseCssColor('#0d1117');
      expect(color, isNotNull);
      expect(color, const Color(0xFF0D1117));
      expect(color!.computeLuminance() < 0.5, isTrue);
    });

    test('parses 3-digit hex correctly', () {
      final color = parseCssColor('#fff');
      expect(color, isNotNull);
      expect(color, const Color(0xFFFFFFFF));
      expect(color!.computeLuminance() >= 0.5, isTrue, reason: '#fff should be light');
    });

    test('parses 8-digit hex (CSS rrggbbaa) correctly', () {
      final color = parseCssColor('#12121280');
      expect(color, isNotNull);
      expect(color!.a, closeTo(0x80 / 255.0, 0.01));
      expect(color.r, closeTo(0x12 / 255.0, 0.01));
    });

    test('parses rgb and rgba correctly', () {
      final rgb = parseCssColor('rgb(18, 18, 18)');
      expect(rgb, isNotNull);
      expect(rgb, const Color(0xFF121212));

      final rgba = parseCssColor('rgba(255, 255, 255, 0.9)');
      expect(rgba, isNotNull);
      expect(rgba!.computeLuminance() >= 0.5, isTrue);
    });

    test('parses hsla correctly', () {
      final hsl = parseCssColor('hsl(0, 0%, 10%)');
      expect(hsl, isNotNull);
      expect(hsl!.computeLuminance() < 0.5, isTrue);
    });

    test('parses named colors correctly', () {
      expect(parseCssColor('black'), Colors.black);
      expect(parseCssColor('white'), Colors.white);
    });

    test('returns null for invalid or transparent inputs', () {
      expect(parseCssColor(null), isNull);
      expect(parseCssColor(''), isNull);
      expect(parseCssColor('transparent'), isNull);
      expect(parseCssColor('inherit'), isNull);
      expect(parseCssColor('invalid-color-value'), isNull);
    });
  });
}
