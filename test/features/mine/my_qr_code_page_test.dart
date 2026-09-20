import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/mine/presentation/my_qr_code_page.dart';
import 'package:gotoim_flutter/features/session/data/models/chat_owner.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  group('MyQrCodePage', () {
    testWidgets('renders user avatar, name, id, and QR code view', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const owner = ChatOwner(
        id: 8848,
        name: '测试专家',
        imageUrl: null,
        typeDescription: '平台管理员',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: MyQrCodePage(owner: owner),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('我的二维码名片'), findsOneWidget);
      expect(find.text('测试专家'), findsOneWidget);
      expect(find.text('平台管理员'), findsOneWidget);
      expect(find.text('账号ID: 8848'), findsOneWidget);
      expect(find.text('扫一扫上面的二维码图案，加我为好友'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('复制链接'), findsOneWidget);
      expect(find.text('保存至相册'), findsOneWidget);
    });

    testWidgets('can copy QR link to clipboard', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const owner = ChatOwner(
        id: 1001,
        name: '张三',
        imageUrl: null,
        typeDescription: '普通用户',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: MyQrCodePage(owner: owner),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final copyButton = find.byIcon(Icons.copy_rounded).first;
      expect(copyButton, findsOneWidget);
      await tester.tap(copyButton);
      await tester.pump();

      expect(find.text('名片链接已复制到剪贴板'), findsOneWidget);
    });
  });
}
