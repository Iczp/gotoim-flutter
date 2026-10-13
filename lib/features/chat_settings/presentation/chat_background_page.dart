import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/media/image_provider_factory.dart';
import '../../../core/utils/api_url_resolver.dart';
import '../../../core/widgets/app_modal.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/cell_group.dart';
import '../application/chat_settings_controller.dart';
import 'chat_background_preview_page.dart';

/// 设置聊天背景页面
///
/// 核心功能：
/// 1. 显示当前使用的聊天背景（卡片展示与状态）；
/// 2. 删除当前背景时弹出二次确认；
/// 3. 提供「从相册选择」和「拍照」选项；
/// 4. 选取背景后进入全屏真实气泡效果预览，点击【应用】才真正提交至服务端。
class ChatBackgroundPage extends ConsumerStatefulWidget {
  const ChatBackgroundPage({
    required this.controller,
    super.key,
  });

  final ChatSettingsController controller;

  @override
  ConsumerState<ChatBackgroundPage> createState() => _ChatBackgroundPageState();
}

class _ChatBackgroundPageState extends ConsumerState<ChatBackgroundPage> {
  ChatSettingsController get controller => widget.controller;

  String? _resolveCurrentBgUrl() {
    final rawBg = controller.backgroundImage;
    if (rawBg == null || rawBg.isEmpty) return null;
    final apiBaseUrl = ref.watch(appEnvironmentProvider).apiBaseUrl;
    return resolveApiUrl(rawBg, apiBaseUrl);
  }

  Future<void> _pickAndPreview(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ChatBackgroundPreviewPage(
          controller: controller,
          chatTitle: controller.title,
          initialImageBytes: bytes,
          initialPickedFile: picked,
        ),
      ),
    );

    if (result == true && mounted) {
      await controller.refresh();
      setState(() {});
    }
  }

  Future<void> _previewCurrentBackground(String bgUrl) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ChatBackgroundPreviewPage(
          controller: controller,
          chatTitle: controller.title,
          currentImageUrl: bgUrl,
        ),
      ),
    );

    if (result == true && mounted) {
      await controller.refresh();
      setState(() {});
    }
  }

  Future<void> _confirmClearBackground() async {
    final confirmed = await showConfirmModal(
      context: context,
      title: '删除聊天背景',
      message: '确定要删除当前聊天背景并恢复默认吗？',
      confirmText: '确认删除',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    try {
      await controller.clearBackgroundImage();
      if (mounted) {
        showToast('聊天背景已删除', type: ToastType.success);
        await controller.refresh();
        setState(() {});
      }
    } catch (error) {
      if (mounted) {
        showToast('删除背景失败：$error', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bgUrl = _resolveCurrentBgUrl();
    final hasBg = bgUrl != null && bgUrl.isNotEmpty;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('聊天背景'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // ── 1. 当前背景卡片 ──
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: hasBg ? () => _previewCurrentBackground(bgUrl) : null,
                  child: Container(
                    width: 170,
                    height: 280,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: hasBg
                            ? colorScheme.primary.withValues(alpha: 0.4)
                            : colorScheme.outlineVariant.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      image: hasBg
                          ? DecorationImage(
                              image: createImageProvider(bgUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: hasBg
                        ? Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(14),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.fullscreen_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      '点击预览大图',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.wallpaper_rounded,
                                  size: 44,
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.4),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '默认背景',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  hasBg ? '当前背景：已设置个性化背景' : '当前背景：系统默认背景',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (hasBg) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.error,
                    ),
                    onPressed: _confirmClearBackground,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('删除当前背景'),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── 2. 选择新背景选项 ──
          CellGroup(
            title: '选择背景',
            children: [
              Cell(
                icon: const Icon(Icons.photo_library_outlined),
                title: '从手机相册选择',
                showArrow: true,
                onTap: () => _pickAndPreview(ImageSource.gallery),
              ),
              Cell(
                icon: const Icon(Icons.camera_alt_outlined),
                title: '拍一张照片',
                showArrow: true,
                onTap: () => _pickAndPreview(ImageSource.camera),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
