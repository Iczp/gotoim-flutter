import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// 桌面端系统托盘图标角标动态生成器
///
/// 核心原理：
/// 1. Windows 原生系统托盘仅支持图标文件 (.ico / .png)，不支持直接传文字角标；
/// 2. 在内存中通过 ui.PictureRecorder + Canvas 将 App 基础图标与未读数字实时合成；
/// 3. 输出为高保真 PNG 并持久化至临时缓存，通过 trayManager.setIcon() 切换图标；
/// 4. 支持呼吸闪烁状态图标生成（高亮态与微光态）。
class TrayBadgeGenerator {
  const TrayBadgeGenerator();

  static final Map<int, String> _badgeCache = <int, String>{};

  static final Map<int, Future<String?>> _pending = {};

  /// 生成带角标数字的托盘图标，并返回文件绝对路径
  static Future<String?> generateBadgeIconPath({
    required int unreadCount,
    bool isDimmed = false,
  }) {
    final count = unreadCount.clamp(0, 100);
    final key = count * 10 + (isDimmed ? 1 : 0);
    return _pending.putIfAbsent(
      key,
      () => _generate(count, isDimmed).whenComplete(() {
        _pending.remove(key);
      }),
    );
  }

  static Future<String?> _generate(int unreadCount, bool isDimmed) async {
    if (kIsWeb ||
        (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux)) {
      return null;
    }

    final cacheKey = unreadCount * 10 + (isDimmed ? 1 : 0);
    if (_badgeCache.containsKey(cacheKey)) {
      final cachedFile = File(_badgeCache[cacheKey]!);
      if (cachedFile.existsSync()) {
        return cachedFile.path;
      }
    }

    try {
      const size = 32.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

      // 1. 绘制底层 App 图标 (微信绿圆角矩阵)
      final basePaint =
          Paint()
            ..color =
                isDimmed
                    ? const Color(0xFF07C160).withValues(alpha: 0.3)
                    : const Color(0xFF07C160)
            ..style = PaintingStyle.fill;

      final baseRRect = RRect.fromRectAndRadius(
        const Rect.fromLTWH(2, 2, 28, 28),
        const Radius.circular(6),
      );
      canvas.drawRRect(baseRRect, basePaint);

      // 绘制白色微型 "IM" 标识
      final textStyle = ui.TextStyle(
        color: isDimmed ? const Color(0x60FFFFFF) : const Color(0xFFFFFFFF),
        fontSize: 12,
        fontWeight: FontWeight.w900,
        fontFamily: 'Microsoft YaHei',
      );
      final paragraphStyle = ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: 12,
      );
      final paragraphBuilder =
          ui.ParagraphBuilder(paragraphStyle)
            ..pushStyle(textStyle)
            ..addText('IM');
      final paragraph =
          paragraphBuilder.build()
            ..layout(const ui.ParagraphConstraints(width: 28));
      canvas.drawParagraph(paragraph, const Offset(2, 8));

      // 2. 绘制未读数字角标 (若 unreadCount > 0)
      if (unreadCount > 0 && !isDimmed) {
        final badgePaint =
            Paint()
              ..color = const Color(0xFFFA5151)
              ..style = PaintingStyle.fill;

        final strokePaint =
            Paint()
              ..color = const Color(0xFF1E1E1E)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5;

        final badgeText = unreadCount > 99 ? '99+' : '$unreadCount';
        final isWide = badgeText.length >= 2;

        final badgeRect =
            isWide
                ? const Rect.fromLTWH(14, 0, 18, 14)
                : const Rect.fromLTWH(18, 0, 14, 14);

        final badgeRRect = RRect.fromRectAndRadius(
          badgeRect,
          Radius.circular(isWide ? 7 : 7),
        );

        canvas.drawRRect(badgeRRect, badgePaint);
        canvas.drawRRect(badgeRRect, strokePaint);

        // 绘制白色角标数字
        final badgeNumStyle = ui.TextStyle(
          color: const Color(0xFFFFFFFF),
          fontSize: isWide ? 8.5 : 9.5,
          fontWeight: FontWeight.bold,
          fontFamily: 'Microsoft YaHei',
        );
        final badgePStyle = ui.ParagraphStyle(
          textAlign: TextAlign.center,
          fontSize: isWide ? 8.5 : 9.5,
        );
        final badgeBuilder =
            ui.ParagraphBuilder(badgePStyle)
              ..pushStyle(badgeNumStyle)
              ..addText(badgeText);
        final badgeP =
            badgeBuilder.build()
              ..layout(ui.ParagraphConstraints(width: badgeRect.width));

        canvas.drawParagraph(
          badgeP,
          Offset(badgeRect.left, badgeRect.top + (isWide ? 1.5 : 1.0)),
        );
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(size.toInt(), size.toInt());
      picture.dispose();
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (byteData == null) return null;

      final tempDir = await getTemporaryDirectory();
      final png = byteData.buffer.asUint8List();
      Uint8List bytes = png;
      if (Platform.isWindows) {
        // Vista+ ICO embeds PNG data; LoadImage(IMAGE_ICON) requires its directory.
        final header =
            ByteData(22)
              ..setUint16(2, 1, Endian.little)
              ..setUint16(4, 1, Endian.little)
              ..setUint8(6, 32)
              ..setUint8(7, 32)
              ..setUint16(10, 1, Endian.little)
              ..setUint16(12, 32, Endian.little)
              ..setUint32(14, png.length, Endian.little)
              ..setUint32(18, 22, Endian.little);
        bytes = Uint8List.fromList([...header.buffer.asUint8List(), ...png]);
      }
      final extension = Platform.isWindows ? 'ico' : 'png';
      final targetFile = File(
        '${tempDir.path}/gotoim_tray_badge_${pid}_${unreadCount}_${isDimmed ? "dim" : "normal"}.$extension',
      );
      await targetFile.writeAsBytes(bytes, flush: true);

      _badgeCache[cacheKey] = targetFile.path;
      return targetFile.path;
    } catch (e) {
      debugPrint('[TrayBadgeGenerator] Failed to generate badge icon: $e');
      return null;
    }
  }
}
