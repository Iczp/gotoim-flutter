import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/theme/tab_glass_controller.dart';

class FakeTabGlassStorage implements TabGlassStorage {
  bool enabled = true;

  @override
  Future<bool> read() async => enabled;

  @override
  Future<void> save(bool value) async {
    enabled = value;
  }
}

void main() {
  test('TabGlassController defaults to true and updates persistence', () async {
    final fakeStorage = FakeTabGlassStorage();
    final container = ProviderContainer(
      overrides: [
        tabGlassStorageProvider.overrideWithValue(fakeStorage),
      ],
    );
    addTearDown(container.dispose);

    // Initial state
    expect(container.read(tabGlassProvider), isTrue);

    // Update to false
    await container.read(tabGlassProvider.notifier).setEnabled(false);
    expect(container.read(tabGlassProvider), isFalse);
    expect(fakeStorage.enabled, isFalse);

    // Update back to true
    await container.read(tabGlassProvider.notifier).setEnabled(true);
    expect(container.read(tabGlassProvider), isTrue);
    expect(fakeStorage.enabled, isTrue);
  });
}
