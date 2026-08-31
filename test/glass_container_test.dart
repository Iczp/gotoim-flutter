import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/theme/app_theme.dart';
import 'package:gotoim_flutter/core/widgets/glass_container.dart';

void main() {
  group('GlassContainer & Glass Components', () {
    testWidgets('renders GlassContainer with child and default blur', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: const Scaffold(
            body: GlassContainer(child: Text('Glass Content')),
          ),
        ),
      );

      expect(find.text('Glass Content'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.byType(ClipRRect), findsOneWidget);
    });

    testWidgets('renders GlassCard with margin and specular border', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(
            body: GlassCard(child: Text('Glass Card Content')),
          ),
        ),
      );

      expect(find.text('Glass Card Content'), findsOneWidget);
      expect(find.byType(GlassContainer), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('renders GlassAppBar with title and toolbar actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            appBar: GlassAppBar(
              title: const Text('Glass App Bar'),
              actions: [
                IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
              ],
            ),
            body: const Center(child: Text('Body Content')),
          ),
        ),
      );

      expect(find.text('Glass App Bar'), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });
}
