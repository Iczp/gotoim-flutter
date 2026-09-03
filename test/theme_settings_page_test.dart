import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/theme/font_scale_controller.dart';
import 'package:gotoim_flutter/core/theme/tab_glass_controller.dart';
import 'package:gotoim_flutter/core/theme/theme_mode_controller.dart';
import 'package:gotoim_flutter/features/settings/presentation/theme_settings_page.dart';

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'APP_NAME=Test'));

  testWidgets('ThemeSettingsPage renders preview and controls, responds to font and mode change', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ThemeSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Title and Sections
    expect(find.text('外观与主题'), findsOneWidget);
    expect(find.text('实时效果预览'), findsOneWidget);
    expect(find.text('主题模式'), findsOneWidget);
    expect(find.text('字体大小'), findsOneWidget);
    expect(find.text('动效与视觉细节'), findsOneWidget);

    // Verify Preview Content
    expect(find.text('Goto IM 架构助理'), findsOneWidget);
    expect(find.text('字号: 标准'), findsOneWidget);

    // Change font scale by tapping "大"
    await tester.tap(find.text('大').last);
    await tester.pumpAndSettle();

    expect(container.read(fontScaleProvider), equals(FontScaleLevel.large.scale));
    expect(find.text('字号: 大'), findsOneWidget);

    // Change ThemeMode to Dark
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), equals(ThemeMode.dark));

    // Toggle tab glass
    final initialGlass = container.read(tabGlassProvider);
    await tester.tap(find.text('底部导航毛玻璃效果'));
    await tester.pumpAndSettle();
    expect(container.read(tabGlassProvider), equals(!initialGlass));
  });
}
