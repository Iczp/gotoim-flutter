import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import '../../../core/widgets/app_avatar.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/file/file_picker_service.dart';
import '../../../core/services/media/media_service.dart';
import '../application/social_identity_controller.dart';
import '../application/social_publish_controller.dart';
import '../data/social_repository.dart';

/// Social Post Composer (Combines Screenshot 1 with X.com modern ergonomics).
class SocialPublishPage extends ConsumerStatefulWidget {
  const SocialPublishPage({super.key});

  @override
  ConsumerState<SocialPublishPage> createState() => _SocialPublishPageState();
}

class _SocialPublishPageState extends ConsumerState<SocialPublishPage> {
  final _textController = TextEditingController();
  late final SocialPublishController _controller;
  bool _preparing = false;
  int _visibility = 0; // 0: 公开, 1: 关注者, 3: 仅自己
  String? _selectedLocation;
  final List<String> _selectedMentionUsers = [];
  final List<XFile> _selectedImages = [];
  SelectedFile? _selectedVideo;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _controller = SocialPublishController(
      ref.read(socialRepositoryProvider),
      actor: ref.read(socialIdentityProvider).actor,
    );
    _textController.addListener(() => setState(() {}));
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_selectedVideo != null) return;
    if (_selectedImages.length >= 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('最多只能添加 4 张图片')));
      return;
    }
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _selectedImages.add(image));
    }
  }

  Future<void> _pickVideo() async {
    if (_selectedImages.isNotEmpty || _selectedVideo != null) return;
    try {
      final video = await ref
          .read(mediaServiceProvider)
          .chooseVideo(const MediaPickRequest());
      if (!mounted || video == null) return;
      if (video.size <= 0 || video.size > 100 * 1024 * 1024) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('视频大小必须在 100 MB 以内')));
        return;
      }
      if (!video.name.toLowerCase().endsWith('.mp4') &&
          !video.name.toLowerCase().endsWith('.webm')) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('目前仅支持 MP4 或 WebM 视频')));
        return;
      }
      setState(() => _selectedVideo = video);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法选择视频，请重试')));
      }
    }
  }

  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  Future<void> _handleAiHelp() async {
    final currentText = _textController.text;
    if (currentText.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先输入一段简要的想法或关键词')));
      return;
    }

    // AI polish/enhance simulation
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('AI 正在润色生成文案…'),
                  ],
                ),
              ),
            ),
          ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) {
      Navigator.of(context).pop();
      setState(() {
        _textController.text = '$currentText #生活碎片 #日常分享 ✨ 记录这一刻的美好与思考。';
      });
    }
  }

  void _selectLocation() {
    setState(() {
      _selectedLocation = _selectedLocation == null ? '北京市·朝阳区' : null;
    });
  }

  void _addMention() {
    final actor = ref.read(socialIdentityProvider).actor;
    if (actor != null && !_selectedMentionUsers.contains(actor.name)) {
      setState(() {
        _selectedMentionUsers.add(actor.name);
      });
    }
  }

  Future<void> _publish() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _selectedImages.isEmpty && _selectedVideo == null) {
      return;
    }

    if (_preparing || _controller.submitting) return;
    setState(() => _preparing = true);
    try {
      final images = await Future.wait(
        _selectedImages.map(
          (image) async => MultipartUploadFile(
            name: image.name,
            length: await image.length(),
            openRead: image.openRead,
            contentType: image.mimeType,
          ),
        ),
      );
      if (!mounted) return;
      final result = await _controller.publish(
        text,
        visibility: _visibility,
        images: images,
        videoSelectionId: _selectedVideo?.id,
        video:
            _selectedVideo == null
                ? null
                : MultipartUploadFile(
                  name: _selectedVideo!.name,
                  length: _selectedVideo!.size,
                  openRead: _selectedVideo!.readAsByteStream,
                  contentType:
                      _selectedVideo!.name.toLowerCase().endsWith('.webm')
                          ? 'video/webm'
                          : 'video/mp4',
                ),
      );
      if (result != null && mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法读取媒体文件，请重新选择后重试')));
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  String _visibilityLabel(int value) => switch (value) {
    0 => '公开',
    1 => '关注者',
    3 => '仅自己',
    _ => '公开',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actor = ref.watch(socialIdentityProvider).actor;
    final charCount = _textController.text.length;
    final canPublish =
        (charCount > 0 ||
            _selectedImages.isNotEmpty ||
            _selectedVideo != null) &&
        !_controller.submitting &&
        !_preparing;

    return PopScope(
      canPop: !_controller.submitting && !_preparing,
      child: Scaffold(
        appBar: AppBar(
          leading: TextButton(
            onPressed:
                _controller.submitting
                    ? null
                    : () => Navigator.of(context).pop(),
            child: Text(
              '取消',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 15,
              ),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00BA7C), // 还原截图 1 的绿色发表胶囊
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: canPublish ? _publish : null,
                child:
                    _controller.submitting
                        ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Text(
                          '发表',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
              ),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (_preparing || _controller.submitting) ...[
                  const SizedBox(height: 12),
                  Text(
                    _controller.uploading
                        ? '正在上传${_selectedVideo == null ? '图片' : '视频'} ${_controller.uploadIndex}/${_controller.uploadCount}${_controller.uploadProgress == null ? '' : ' · ${(_controller.uploadProgress! * 100).round()}%'}'
                        : _controller.submitting
                        ? '正在发表动态…'
                        : '正在准备媒体…',
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value:
                        _controller.uploading
                            ? _controller.uploadProgress
                            : null,
                  ),
                ],
                const SizedBox(height: 12),

                // Author Row + Visibility Tag
                Row(
                  children: [
                    AppAvatar(
                      name: actor?.name ?? 'User',
                      imageUrl: actor?.avatarUrl,
                      radius: 18,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          actor?.name ?? '社交用户',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '@${actor?.handle ?? 'user'}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Free-form Input Area (Prompt in Screenshot 1: "这一刻的想法...")
                TextField(
                  controller: _textController,
                  enabled: !_controller.submitting,
                  minLines: 4,
                  maxLines: 10,
                  maxLength: 1000,
                  style: const TextStyle(fontSize: 16, height: 1.4),
                  decoration: const InputDecoration(
                    hintText: '这一刻的想法…',
                    hintStyle: TextStyle(color: Colors.grey, fontSize: 16),
                    border: InputBorder.none,
                    counterText: '',
                  ),
                ),

                const SizedBox(height: 12),

                // Media 9-Grid Preview (Adding & Deleting Photos)
                _buildPhotoGrid(theme),

                const SizedBox(height: 16),

                // "AI 帮写" Quick Row (Screenshot 1: "•• AI帮写")
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _handleAiHelp,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            const Text(
                              '•• ',
                              style: TextStyle(
                                color: Color(0xFF1D9BF0),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'AI帮写',
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.8,
                                ),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                const Divider(height: 1, thickness: 0.5),

                // 1. 所在位置
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.location_on_outlined, size: 22),
                  title: const Text('所在位置', style: TextStyle(fontSize: 15)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_selectedLocation != null)
                        Text(
                          _selectedLocation!,
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 13,
                          ),
                        ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                  onTap: _selectLocation,
                ),
                const Divider(height: 1, thickness: 0.5),

                // 2. 提醒谁看
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.alternate_email_rounded, size: 22),
                  title: const Text('提醒谁看', style: TextStyle(fontSize: 15)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_selectedMentionUsers.isNotEmpty)
                        Text(
                          _selectedMentionUsers.join(', '),
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 13,
                          ),
                        ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                  onTap: _addMention,
                ),
                const Divider(height: 1, thickness: 0.5),

                // 3. 谁可以看
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline_rounded, size: 22),
                  title: const Text('谁可以看', style: TextStyle(fontSize: 15)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _visibilityLabel(_visibility),
                        style: TextStyle(
                          color: theme.textTheme.bodySmall?.color,
                          fontSize: 14,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                  onTap: _showVisibilitySheet,
                ),
                const Divider(height: 1, thickness: 0.5),

                if (_controller.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      _controller.error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoGrid(ThemeData theme) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (_selectedVideo != null)
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child:
                      _controller.uploading
                          ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                value: _controller.uploadProgress,
                              ),
                              if (_controller.uploadProgress != null)
                                Text(
                                  '${(_controller.uploadProgress! * 100).round()}%',
                                ),
                            ],
                          )
                          : const Icon(Icons.videocam, size: 36),
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: IconButton(
                  onPressed:
                      _preparing || _controller.submitting
                          ? null
                          : () => setState(() => _selectedVideo = null),
                  icon: const Icon(Icons.cancel),
                  tooltip: '移除视频',
                ),
              ),
            ],
          ),
        ...List.generate(_selectedImages.length, (index) {
          final file = _selectedImages[index];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: DecorationImage(
                    image: FileImage(File(file.path)),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              if (_controller.submitting &&
                  _controller.uploadIndex > 0 &&
                  index < _controller.uploadIndex)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child:
                          index + 1 < _controller.uploadIndex ||
                                  !_controller.uploading
                              ? const Icon(
                                Icons.check_circle,
                                color: Colors.white,
                              )
                              : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      value: _controller.uploadProgress,
                                      color: Colors.white,
                                      strokeWidth: 3,
                                    ),
                                  ),
                                  if (_controller.uploadProgress != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${(_controller.uploadProgress! * 100).round()}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                    ),
                  ),
                ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap:
                      _preparing || _controller.submitting
                          ? null
                          : () => _removeImage(index),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
        if (_selectedVideo == null && _selectedImages.length < 4)
          GestureDetector(
            onTap: _preparing || _controller.submitting ? null : _pickImage,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.add, size: 38, color: Colors.black38),
            ),
          ),
        if (_selectedImages.isEmpty && _selectedVideo == null)
          GestureDetector(
            onTap: _preparing || _controller.submitting ? null : _pickVideo,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.video_call_outlined, size: 32),
                  Text('选择视频'),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _showVisibilitySheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('公开'),
                  subtitle: const Text('所有人可见'),
                  trailing:
                      _visibility == 0
                          ? const Icon(Icons.check, color: Color(0xFF00BA7C))
                          : null,
                  onTap: () {
                    setState(() => _visibility = 0);
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  title: const Text('关注者'),
                  subtitle: const Text('仅关注你的人可见'),
                  trailing:
                      _visibility == 1
                          ? const Icon(Icons.check, color: Color(0xFF00BA7C))
                          : null,
                  onTap: () {
                    setState(() => _visibility = 1);
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  title: const Text('仅自己'),
                  subtitle: const Text('仅自己可见'),
                  trailing:
                      _visibility == 3
                          ? const Icon(Icons.check, color: Color(0xFF00BA7C))
                          : null,
                  onTap: () {
                    setState(() => _visibility = 3);
                    Navigator.of(ctx).pop();
                  },
                ),
              ],
            ),
          ),
    );
  }
}
