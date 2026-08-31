import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/workbench/application/webview_session.dart';

void main() {
  test('registry preserves one session state until explicit release', () {
    final registry = WebViewSessionRegistry.shared;
    const id = 'test-webview-session';
    registry.release(id);

    final first = registry.obtain(
      id: id,
      url: Uri.parse('https://example.test/start'),
      title: '起始页',
    );
    first.didChangeTitle('二级页面');
    first.didStart(Uri.parse('https://example.test/details'));
    final same = registry.obtain(
      id: id,
      url: Uri.parse('https://example.test/start'),
    );

    expect(identical(first, same), isTrue);
    expect(same.currentUrl.path, '/details');
    expect(same.history.map((url) => url.path), <String>['/start', '/details']);
    expect(same.title, '二级页面');
    expect(same.loading, isTrue);
    expect(same.jsBridgeStatus, WebViewJsBridgeStatus.unbound);
    first.markJsBridgeAttached();
    first.recordJsBridgeRequest();
    expect(same.jsBridgeStatus, WebViewJsBridgeStatus.attached);
    expect(same.jsBridgeRequestCount, 1);
    first.minimize();
    expect(same.minimized, isTrue);
    first.restore();
    expect(same.minimized, isFalse);

    registry.release(id);
    expect(registry.find(id), isNull);
  });
}
