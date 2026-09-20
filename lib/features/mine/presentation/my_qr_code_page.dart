import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/services/media/media_gallery_saver.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/data/models/chat_owner.dart';

/// 独立的个人名片二维码页面。
///
/// 支持高保真展示、截图保存至本地系统相册、复制名片链接与分享。
class MyQrCodePage extends ConsumerStatefulWidget {
  const MyQrCodePage({
    this.owner,
    super.key,
  });

  final ChatOwner? owner;

  @override
  ConsumerState<MyQrCodePage> createState() => _MyQrCodePageState();
}

class _MyQrCodePageState extends ConsumerState<MyQrCodePage> {
  final GlobalKey _cardKey = GlobalKey();
  bool _isSaving = false;

  String _buildQrData(ChatOwner? owner) {
    final id = owner?.id ?? 0;
    final name = owner?.name ?? 'GotoIM用户';
    return 'gotoim://user/?id=$id&name=${Uri.encodeComponent(name)}';
  }

  Future<void> _saveQrImageToGallery() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('无法获取名片视图渲染层');
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('名片图片数据转换失败');
      }
      final bytes = byteData.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}${Platform.pathSeparator}gotoim_qr_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(bytes);

      final success = await MediaGallerySaver.saveImage(tempFile.path);
      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('名片二维码已成功保存到系统相册'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('保存到相册失败，请检查存储权限'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _copyQrLink(String qrData) {
    Clipboard.setData(ClipboardData(text: qrData));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('名片链接已复制到剪贴板'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ChatOwner? owner;
    if (widget.owner != null) {
      owner = widget.owner;
    } else {
      owner = ref.watch(sessionListControllerProvider).currentOwner;
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final name = owner?.name ?? 'GotoIM 用户';
    final qrData = _buildQrData(owner);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('我的二维码名片'),
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 20),
            tooltip: '复制名片链接',
            onPressed: () => _copyQrLink(qrData),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 可保存截图的名片主体卡片 ────────────────────────────────────
                  RepaintBoundary(
                    key: _cardKey,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                      decoration: BoxDecoration(
                        color: isDark ? colorScheme.surfaceContainerHigh : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                child: Text(
                                  name.isNotEmpty ? name.characters.first : '?',
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 17,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      owner?.typeDescription.isNotEmpty == true
                                          ? owner!.typeDescription
                                          : 'GotoIM 专属名片',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    if (owner?.id != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '账号ID: ${owner!.id}',
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: colorScheme.outline,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Container(
                            width: 220,
                            height: 220,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.grey.withValues(alpha: 0.15),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: QrImageView(
                              data: qrData,
                              version: QrVersions.auto,
                              size: 200,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            '扫一扫上面的二维码图案，加我为好友',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── 底部快捷操作按钮 ───────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _copyQrLink(qrData),
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('复制链接'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isSaving ? null : _saveQrImageToGallery,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_alt_rounded, size: 18),
                          label: Text(_isSaving ? '保存中...' : '保存至相册'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
