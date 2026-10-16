// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:crypto/crypto.dart';

/// Generates a deterministic device ID using browser fingerprinting.
///
/// Collects high-entropy, hardware- and browser-specific metrics:
/// - Navigator properties (UserAgent, language, cores, maxTouchPoints, platform, vendor)
/// - Screen and display metrics (resolution, color depth, devicePixelRatio)
/// - Timezone offsets and locale
/// - Canvas 2D text & shape rendering (GPU font rasterization and color compositing differences)
/// - WebGL graphics driver vendor and renderer strings
///
/// Returns a canonical UUID formatted string (8-4-4-4-12) derived from SHA-256.
Future<String?> getBrowserFingerprint() async {
  try {
    final components = <String>[];

    final windowObj = globalContext['window'] as JSObject?;
    final nav = globalContext['navigator'] as JSObject?;
    final screen = globalContext['screen'] as JSObject?;
    final doc = globalContext['document'] as JSObject?;

    // 1. Navigator information
    if (nav != null) {
      void addNavProp(String key) {
        try {
          final val = nav[key];
          if (val != null) components.add('$key:$val');
        } catch (_) {}
      }

      addNavProp('userAgent');
      addNavProp('language');
      addNavProp('languages');
      addNavProp('platform');
      addNavProp('hardwareConcurrency');
      addNavProp('maxTouchPoints');
      addNavProp('deviceMemory');
      addNavProp('vendor');
      addNavProp('appCodeName');
      addNavProp('appName');
    }

    // 2. Screen & Display metrics
    if (screen != null) {
      void addScreenProp(String key) {
        try {
          final val = screen[key];
          if (val != null) components.add('screen.$key:$val');
        } catch (_) {}
      }

      addScreenProp('width');
      addScreenProp('height');
      addScreenProp('colorDepth');
      addScreenProp('pixelDepth');
    }
    if (windowObj != null) {
      try {
        final dpr = windowObj['devicePixelRatio'];
        if (dpr != null) components.add('dpr:$dpr');
      } catch (_) {}
    }

    // 3. Timezone information
    try {
      final now = DateTime.now();
      components.add('tzName:${now.timeZoneName}');
      components.add('tzOffset:${now.timeZoneOffset.inMinutes}');
    } catch (_) {}

    // 4. Canvas & WebGL fingerprinting
    if (doc != null) {
      try {
        final canvas = doc.callMethod<JSObject>(
          'createElement'.toJS,
          'canvas'.toJS,
        );
        canvas['width'] = 240.toJS;
        canvas['height'] = 60.toJS;

        // 2D Canvas rendering
        final ctx = canvas.callMethod<JSObject?>('getContext'.toJS, '2d'.toJS);
        if (ctx != null) {
          ctx['textBaseline'] = 'alphabetic'.toJS;
          ctx['font'] = "14px 'Arial', 'Helvetica', sans-serif".toJS;
          ctx['fillStyle'] = '#f60'.toJS;
          ctx.callMethod<JSAny?>(
            'fillRect'.toJS,
            125.toJS,
            1.toJS,
            62.toJS,
            20.toJS,
          );
          ctx['fillStyle'] = '#069'.toJS;
          ctx.callMethod<JSAny?>(
            'fillText'.toJS,
            'GotoIM BrowserID v1,😃'.toJS,
            2.toJS,
            15.toJS,
          );
          ctx['fillStyle'] = 'rgba(102, 204, 0, 0.7)'.toJS;
          ctx.callMethod<JSAny?>(
            'fillText'.toJS,
            'GotoIM BrowserID v1,😃'.toJS,
            4.toJS,
            17.toJS,
          );
          final dataUrl = canvas.callMethod<JSString>('toDataURL'.toJS).toDart;
          components.add('canvas:$dataUrl');
        }

        // WebGL graphics renderer
        final gl =
            canvas.callMethod<JSObject?>('getContext'.toJS, 'webgl'.toJS) ??
            canvas.callMethod<JSObject?>(
              'getContext'.toJS,
              'experimental-webgl'.toJS,
            );
        if (gl != null) {
          final debugInfo = gl.callMethod<JSObject?>(
            'getExtension'.toJS,
            'WEBGL_debug_renderer_info'.toJS,
          );
          if (debugInfo != null) {
            final unmaskedVendor =
                debugInfo['UNMASKED_VENDOR_WEBGL'] as JSNumber?;
            final unmaskedRenderer =
                debugInfo['UNMASKED_RENDERER_WEBGL'] as JSNumber?;
            if (unmaskedVendor != null) {
              final vendor = gl.callMethod<JSAny?>(
                'getParameter'.toJS,
                unmaskedVendor,
              );
              components.add('glVendor:$vendor');
            }
            if (unmaskedRenderer != null) {
              final renderer = gl.callMethod<JSAny?>(
                'getParameter'.toJS,
                unmaskedRenderer,
              );
              components.add('glRenderer:$renderer');
            }
          }
        }
      } catch (_) {}
    }

    if (components.isEmpty) return null;

    final raw = components.join('###');
    final bytes = utf8.encode(raw);
    final digest = sha256.convert(bytes);
    final hex = digest.toString();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  } catch (_) {
    return null;
  }
}
