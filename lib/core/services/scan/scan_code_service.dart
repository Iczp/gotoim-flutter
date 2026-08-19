import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'scan_code_models.dart';
import 'scan_code_page.dart';

export 'scan_code_models.dart';
export 'image_code_decoder.dart';

/// Application-facing scan API.
///
/// It deliberately receives [NavigatorState] rather than a page context so
/// native Flutter pages and a future WebView JS bridge can invoke one API.
abstract class ScanCodeService {
  Future<ScanCodeResult?> scanCode(
    NavigatorState navigator,
    ScanCodeRequest request,
  );
}

final scanCodeServiceProvider = Provider<ScanCodeService>(
  (ref) => const NavigatorScanCodeService(),
);

class NavigatorScanCodeService implements ScanCodeService {
  const NavigatorScanCodeService();

  @override
  Future<ScanCodeResult?> scanCode(
    NavigatorState navigator,
    ScanCodeRequest request,
  ) {
    return navigator.push<ScanCodeResult>(
      PageRouteBuilder<ScanCodeResult>(
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                ScanCodePage(request: request),
        transitionsBuilder:
            (context, animation, secondaryAnimation, child) =>
                FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}
