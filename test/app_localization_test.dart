import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/localization/app_localization.dart';

void main() {
  testWidgets('edit menu defaults to Chinese on an English system', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'en',
      'US',
    );
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    late MaterialLocalizations labels;
    await tester.pumpWidget(
      MaterialApp(
        locale: AppLocalization.locale,
        supportedLocales: AppLocalization.supportedLocales,
        localizationsDelegates: AppLocalization.delegates,
        home: Builder(
          builder: (context) {
            labels = MaterialLocalizations.of(context);
            return const Scaffold(body: TextField());
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(labels.copyButtonLabel, '复制');
    expect(labels.cutButtonLabel, '剪切');
    expect(labels.pasteButtonLabel, '粘贴');
    expect(labels.selectAllButtonLabel, '全选');
  });
}
