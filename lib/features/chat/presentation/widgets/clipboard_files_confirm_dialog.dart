import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../../../../core/services/file/file_picker_service.dart';

/// 剪贴板文件预发送确认对话框 (ClipboardFilesConfirmDialog)
///
/// 核心规范：
/// 1. 微信同款纯净无边框 (border: null)，采用中性黑灰调与 12dp 现代圆角；
/// 2. 支持单文件与批量多文件（按粘贴预发送的文件，可能是很多个）；
/// 3. 展示各文件类型图标、文件名、文件体积与总大小统计；
/// 4. 允许单项移除（剔除误选文件）；
/// 5. 允许附加留言输入；
/// 6. 确定之后调用上传与发送链路。
class ClipboardFilesConfirmDialog extends StatefulWidget {
  const ClipboardFilesConfirmDialog({
    this.filePaths = const <String>[],
    this.initialFiles,
    this.initialCaption,
    super.key,
  });

  final List<String> filePaths;
  final List<SelectedFile>? initialFiles;
  final String? initialCaption;

  /// 弹出文件预发送确认对话框
  static Future<({bool confirmed, List<SelectedFile> files, String? caption})?>
  show(
    BuildContext context, {
    List<String> filePaths = const <String>[],
    List<SelectedFile>? initialFiles,
    String? initialCaption,
  }) {
    return showGeneralDialog<
      ({bool confirmed, List<SelectedFile> files, String? caption})
    >(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'DismissClipboardFiles',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.0).animate(curve),
          child: FadeTransition(opacity: curve, child: child),
        );
      },
      pageBuilder: (context, _, _) {
        return Center(
          child: ClipboardFilesConfirmDialog(
            filePaths: filePaths,
            initialFiles: initialFiles,
            initialCaption: initialCaption,
          ),
        );
      },
    );
  }

  @override
  State<ClipboardFilesConfirmDialog> createState() =>
      _ClipboardFilesConfirmDialogState();
}

class _ClipboardFilesConfirmDialogState
    extends State<ClipboardFilesConfirmDialog> {
  late final TextEditingController _captionController;
  final FocusNode _focusNode = FocusNode();
  final List<SelectedFile> _files = <SelectedFile>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.initialCaption);
    if (widget.initialFiles != null && widget.initialFiles!.isNotEmpty) {
      _files.addAll(widget.initialFiles!);
      _isLoading = false;
    } else {
      _loadFiles();
    }
  }

  Future<void> _loadFiles() async {
    final results = await Future.wait(
      widget.filePaths.map((path) async {
        try {
          final ioFile = File(path);
          if (ioFile.existsSync()) {
            return await SelectedFile.fromXFile(
              // ignore: invalid_use_of_visible_for_testing_member
              XFile(path),
            );
          }
        } catch (_) {}
        return null;
      }),
    );
    if (mounted) {
      setState(() {
        _files.addAll(results.whereType<SelectedFile>());
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _removeFile(int index) {
    setState(() {
      _files.removeAt(index);
    });
    if (_files.isEmpty) {
      _onCancel();
    }
  }

  void _onConfirm() {
    if (_files.isEmpty) return;
    final caption = _captionController.text.trim();
    Navigator.of(context).pop((
      confirmed: true,
      files: _files,
      caption: caption.isNotEmpty ? caption : null,
    ));
  }

  void _onCancel() {
    Navigator.of(
      context,
    ).pop((confirmed: false, files: const <SelectedFile>[], caption: null));
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _getFileIcon(String? ext) => switch ((ext ?? '').toLowerCase()) {
        'pdf' => Icons.picture_as_pdf_rounded,
        'doc' || 'docx' => Icons.description_rounded,
        'xls' || 'xlsx' || 'csv' => Icons.table_chart_rounded,
        'ppt' || 'pptx' => Icons.slideshow_rounded,
        'zip' || 'rar' || '7z' || 'tar' || 'gz' => Icons.folder_zip_rounded,
        'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'bmp' =>
          Icons.image_rounded,
        'mp4' || 'mov' || 'avi' || 'mkv' => Icons.videocam_rounded,
        'mp3' || 'wav' || 'aac' || 'flac' => Icons.audiotrack_rounded,
        _ => Icons.insert_drive_file_rounded,
      };

  Color _getFileColor(String? ext) => switch ((ext ?? '').toLowerCase()) {
        'pdf' => const Color(0xFFFA5151),
        'doc' || 'docx' => const Color(0xFF2B579A),
        'xls' || 'xlsx' || 'csv' => const Color(0xFF217346),
        'ppt' || 'pptx' => const Color(0xFFD24726),
        'zip' || 'rar' || '7z' => const Color(0xFFF39C12),
        'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' => const Color(0xFF07C160),
        _ => const Color(0xFF6B7280),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 微信中性黑灰色阶统一 (#232323 / #1E1E1E)
    final surfaceBg = isDark ? const Color(0xFF232323) : Colors.white;
    final headerBg = isDark ? const Color(0xFF262626) : const Color(0xFFF5F5F5);
    final itemBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F7F7);
    final inputBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEFEFEF);
    final textMain = isDark ? const Color(0xFFF0F0F0) : const Color(0xFF1F2937);
    final textSecondary =
        isDark ? const Color(0xFF9E9E9E) : const Color(0xFF6B7280);
    const accentGreen = Color(0xFF07C160);

    final totalBytes = _files.fold<int>(0, (sum, f) => sum + f.size);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.enter &&
              !HardwareKeyboard.instance.isShiftPressed) {
            _onConfirm();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _onCancel();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 480,
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
          decoration: BoxDecoration(
            color: surfaceBg,
            borderRadius: BorderRadius.circular(12),
            border: null, // 严格无边框
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.25),
                blurRadius: 36,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 顶部标题栏
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                color: headerBg,
                child: Row(
                  children: [
                    const Icon(
                      Icons.folder_open_rounded,
                      size: 18,
                      color: accentGreen,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _files.length > 1 ? '发送文件 (${_files.length} 个)' : '发送文件',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: textMain,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      visualDensity: VisualDensity.compact,
                      tooltip: '关闭 (Esc)',
                      onPressed: _onCancel,
                    ),
                  ],
                ),
              ),

              // 2. 文件列表展示区
              Flexible(
                child:
                    _isLoading
                        ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                        : ListView.separated(
                          padding: const EdgeInsets.all(14),
                          shrinkWrap: true,
                          itemCount: _files.length,
                          separatorBuilder:
                              (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final file = _files[index];
                            final icon = _getFileIcon(file.extension);
                            final iconColor = _getFileColor(file.extension);

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: itemBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  // 文件类型图标
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: iconColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      icon,
                                      size: 20,
                                      color: iconColor,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  // 文件名与大小
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          file.name,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w500,
                                            color: textMain,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _formatSize(file.size),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // 移除该项按钮
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_outline_rounded,
                                      size: 16,
                                      color: textSecondary,
                                    ),
                                    tooltip: '移除此文件',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _removeFile(index),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
              ),

              // 3. 统计微注
              if (_files.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '共 ${_files.length} 个待发送文件',
                        style: TextStyle(fontSize: 11, color: textSecondary),
                      ),
                      Text(
                        '总计 ${_formatSize(totalBytes)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),

              // 4. 附加留言输入框
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: inputBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: TextField(
                    controller: _captionController,
                    focusNode: _focusNode,
                    style: TextStyle(fontSize: 12.5, color: textMain),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: '添加留言 (可选)...',
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: textSecondary.withValues(alpha: 0.7),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 9),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // 5. 底部操作按钮栏 (取消 / 确认发送)
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                color: headerBg,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _onCancel,
                      style: TextButton.styleFrom(
                        foregroundColor: textSecondary,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: const Text('取消 (Esc)'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _files.isNotEmpty ? _onConfirm : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: accentGreen,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _files.length > 1
                            ? '发送 (${_files.length})'
                            : '发送 (Enter)',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
