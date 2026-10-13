import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/media/image_provider_factory.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/app_modal.dart';
import '../../../core/widgets/app_toast.dart';
import '../application/chat_settings_controller.dart';

/// 聊天背景效果预览与应用页面。
///
/// 功能：
/// 1. 全屏展示所选背景或当前背景；
/// 2. 模拟真实聊天对话气泡，直观呈现视觉效果与文字可读性；
/// 3. 用户满意后点击【应用】才提交上传至服务端；放弃直接返回不影响远端。
class ChatBackgroundPreviewPage extends StatefulWidget {
  const ChatBackgroundPreviewPage({
    required this.controller,
    required this.chatTitle,
    this.initialImageBytes,
    this.initialPickedFile,
    this.currentImageUrl,
    super.key,
  });

  final ChatSettingsController controller;
  final String chatTitle;
  final Uint8List? initialImageBytes;
  final XFile? initialPickedFile;
  final String? currentImageUrl;

  @override
  State<ChatBackgroundPreviewPage> createState() =>
      _ChatBackgroundPreviewPageState();
}

class _ChatBackgroundPreviewPageState
    extends State<ChatBackgroundPreviewPage> {
  Uint8List? _previewBytes;
  XFile? _previewFile;
  String? _currentUrl;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _previewBytes = widget.initialImageBytes;
    _previewFile = widget.initialPickedFile;
    _currentUrl = widget.currentImageUrl;
  }

  bool get _hasNewSelection => _previewBytes != null && _previewFile != null;

  ImageProvider? _resolveBackgroundProvider() {
    if (_previewBytes != null) {
      return MemoryImage(_previewBytes!);
    }
    if (_currentUrl != null && _currentUrl!.isNotEmpty) {
      return createImageProvider(_currentUrl!);
    }
    return null;
  }

  Future<void> _pickNewImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    setState(() {
      _previewFile = picked;
      _previewBytes = bytes;
    });
  }

  Future<void> _applyBackground() async {
    if (_previewFile == null || _isApplying) return;

    setState(() => _isApplying = true);
    try {
      await widget.controller.setBackgroundImage(
        MultipartUploadFile(
          name: _previewFile!.name,
          length: await _previewFile!.length(),
          openRead: _previewFile!.openRead,
        ),
      );
      if (mounted) {
        showToast('聊天背景已应用', type: ToastType.success);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        showToast('应用背景失败：$e', type: ToastType.error);
        setState(() => _isApplying = false);
      }
    }
  }

  Future<void> _confirmDeleteBackground() async {
    final confirmed = await showConfirmModal(
      context: context,
      title: '删除聊天背景',
      message: '确定要删除当前聊天背景并恢复默认吗？',
      confirmText: '确认删除',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isApplying = true);
    try {
      await widget.controller.clearBackgroundImage();
      if (mounted) {
        showToast('聊天背景已删除', type: ToastType.success);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        showToast('删除背景失败：$e', type: ToastType.error);
        setState(() => _isApplying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgProvider = _resolveBackgroundProvider();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _hasNewSelection ? '预览新背景' : '当前聊天背景',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        actions: [
          if (!_hasNewSelection && _currentUrl != null && _currentUrl!.isNotEmpty)
            IconButton(
              tooltip: '删除背景',
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
              onPressed: _isApplying ? null : _confirmDeleteBackground,
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── 1. 全屏背景渲染层 ──
          if (bgProvider != null)
            Image(
              image: bgProvider,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            )
          else
            Container(
              color: theme.colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: Text(
                '暂未设置背景',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 16,
                ),
              ),
            ),

          // ── 2. 轻微通透渐变遮罩（确保顶部标题与底部按钮易读） ──
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.25),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.45),
                ],
                stops: const [0.0, 0.18, 0.72, 1.0],
              ),
            ),
          ),

          // ── 3. 模拟聊天消息气泡预览区 ──
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),
                // 时间标签
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '12:00',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 对方消息
                _buildIncomingMessage(
                  text: '这是聊天背景的效果预览。',
                  time: '12:00',
                ),
                const SizedBox(height: 16),

                // 我方消息
                _buildOutgoingMessage(
                  text: _hasNewSelection
                      ? '背景看起来很舒服！满意请点击下方“应用”生效。'
                      : '这是当前正在生效的聊天背景。',
                  time: '12:01',
                  colorScheme: theme.colorScheme,
                ),
                const SizedBox(height: 16),

                // 对方后续消息
                _buildIncomingMessage(
                  text: '支持清晰识别文字与气泡，带来沉浸式聊天体验。',
                  time: '12:02',
                ),

                const Spacer(),

                // ── 4. 底部操作栏 ──
                _buildBottomBar(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomingMessage({
    required String text,
    required String time,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: Colors.white.withValues(alpha: 0.9),
            child: const Icon(Icons.person, color: Colors.black54, size: 22),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black87,
                  height: 1.35,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildOutgoingMessage({
    required String text,
    required String time,
    required ColorScheme colorScheme,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 48),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF07C160).withValues(alpha: 0.95),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.white,
                  height: 1.35,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 19,
            backgroundColor: const Color(0xFF07C160),
            child: const Icon(Icons.person, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white60),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _isApplying ? null : _pickNewImage,
              icon: const Icon(Icons.photo_library_outlined, size: 20),
              label: Text(
                _hasNewSelection ? '更换图片' : '从相册选择',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (_hasNewSelection) ...[
            const SizedBox(width: 14),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF07C160),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isApplying ? null : _applyBackground,
                icon: _isApplying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 20),
                label: Text(
                  _isApplying ? '正在应用...' : '应用',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
