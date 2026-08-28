import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/theme/overscroll_style_controller.dart';

class _FakeOverscrollStyleStorage implements OverscrollStyleStorage {
  OverscrollStyle value = OverscrollStyle.platform;

  @override
  Future<OverscrollStyle> read() async => value;

  @override
  Future<void> save(OverscrollStyle style) async {
    value = style;
  }
}

void main() {
  test('overscroll style changes and persists', () async {
    final storage = _FakeOverscrollStyleStorage();
    final container = ProviderContainer(
      overrides: [overscrollStyleStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    expect(container.read(overscrollStyleProvider), OverscrollStyle.platform);

    await container
        .read(overscrollStyleControllerProvider.notifier)
        .setStyle(OverscrollStyle.bouncing);

    expect(container.read(overscrollStyleProvider), OverscrollStyle.bouncing);
    expect(storage.value, OverscrollStyle.bouncing);
  });
}
