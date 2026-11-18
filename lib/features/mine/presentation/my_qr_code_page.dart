import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/services/media/media_gallery_saver.dart';
import '../../../core/utils/api_url_resolver.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../qr_code/data/models/qr_code_models.dart';
import '../../qr_code/data/qr_code_repository.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/data/models/chat_owner.dart';

/// 独立的个人名片 / 群聊二维码页面。
///
/// 支持多 ChatObjectId 身份切换、永久/7天/30天/自定义天数、重置二维码、保存相册与复制链接。
class MyQrCodePage extends ConsumerStatefulWidget {
  const MyQrCodePage({
    this.owner,
    this.isGroup = false,
    this.groupOwnerId,
    this.groupTitle,
    this.groupAvatar,
    this.inviterId,
    super.key,
  });

  final ChatOwner? owner;
  final bool isGroup;
  final int? groupOwnerId;
  final String? groupTitle;
  final String? groupAvatar;
  final int? inviterId;

  @override
  ConsumerState<MyQrCodePage> createState() => _MyQrCodePageState();
}

class _MyQrCodePageState extends ConsumerState<MyQrCodePage> {
  final GlobalKey _cardKey = GlobalKey();
  bool _isSaving = false;
  bool _loading = false;
  String? _error;

  int? _selectedOwnerId;
  int? _expireDays; // null 表示个人默认永久或群默认 7 天
  bool? _isPermanent;
  QrCodeDetailModel? _qrDetail;

  @override
  void initState() {
    super.initState();
    final sessionCtrl = ref.read(sessionListControllerProvider);
    _selectedOwnerId = widget.isGroup
        ? widget.groupOwnerId
        : (widget.owner?.id ?? sessionCtrl.currentOwnerId);
    _isPermanent = widget.isGroup ? false : true;
    _expireDays = widget.isGroup ? 7 : null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadQrCode());
  }

  Future<void> _loadQrCode({bool reset = false}) async {
    final targetOwnerId = _selectedOwnerId;
    if (targetOwnerId == null || targetOwnerId <= 0) {
      setState(() => _error = '未找到有效的聊天对象身份');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(qrCodeRepositoryProvider);
      final inviterId = widget.isGroup
          ? (widget.inviterId ??
                ref.read(sessionListControllerProvider).currentOwnerId)
          : null;

      final detail = reset
          ? await repo.reset(
              ownerId: targetOwnerId,
              inviterId: inviterId,
              isPermanent: _isPermanent,
              expireDays: _expireDays,
            )
          : await repo.generate(
              ownerId: targetOwnerId,
              inviterId: inviterId,
              isPermanent: _isPermanent,
              expireDays: _expireDays,
            );
      if (!mounted) return;
      setState(() => _qrDetail = detail);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载二维码失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectValidity({
    required bool isPermanent,
    int? expireDays,
  }) async {
    setState(() {
      _isPermanent = widget.isGroup ? false : isPermanent;
      _expireDays = expireDays;
    });
    await _loadQrCode();
  }

  Future<void> _promptCustomDays() async {
    final textCtrl = TextEditingController(text: '${_expireDays ?? 14}');
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义有效期'),
        content: TextField(
          controller: textCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '有效天数（1 ~ 365）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(textCtrl.text.trim());
              if (val != null && val >= 1 && val <= 365) {
                Navigator.of(ctx).pop(val);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    textCtrl.dispose();
    if (days != null && mounted) {
      await _selectValidity(isPermanent: false, expireDays: days);
    }
  }

  String _formatValidityLabel() {
    final detail = _qrDetail;
    if (detail == null) {
      if (!widget.isGroup && (_isPermanent ?? true)) return '永久有效';
      return '${_expireDays ?? 7}天内有效';
    }
    if (detail.isPermanent) return '该二维码永久有效';
    final exp = detail.expirationTime?.toLocal();
    if (exp == null) return '${detail.expireDays ?? 7}天内有效';
    final y = exp.year;
    final m = exp.month.toString().padLeft(2, '0');
    final d = exp.day.toString().padLeft(2, '0');
    return '有效期至 $y-$m-$d（${detail.expireDays ?? 7}天）';
  }

  Future<void> _saveQrImageToGallery() async {
    if (_isSaving || _qrDetail == null) return;
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '二维码已成功保存到系统相册' : '保存到相册失败，请检查存储权限'),
          duration: const Duration(seconds: 2),
          backgroundColor: success ? Colors.green : null,
        ),
      );
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
        content: Text('二维码链接已复制到剪贴板'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionCtrl = ref.watch(sessionListControllerProvider);
    final owners = sessionCtrl.owners;
    final apiBaseUrl = ref.watch(appEnvironmentProvider).apiBaseUrl;

    ChatOwner? currentPersonalOwner = widget.owner;
    if (!widget.isGroup) {
      currentPersonalOwner = owners.cast<ChatOwner?>().firstWhere(
            (o) => o?.id == _selectedOwnerId,
            orElse: () => widget.owner ?? sessionCtrl.currentOwner,
          );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final name = widget.isGroup
        ? (_qrDetail?.ownerName ?? widget.groupTitle ?? '群聊二维码')
        : (_qrDetail?.ownerName ?? currentPersonalOwner?.name ?? 'GotoIM 用户');

    final subtitle = widget.isGroup
        ? '群聊邀请码'
        : (currentPersonalOwner?.typeDescription.isNotEmpty == true
              ? currentPersonalOwner!.typeDescription
              : 'GotoIM 专属名片');

    final rawAvatar = widget.isGroup
        ? (_qrDetail?.ownerThumbnail ?? widget.groupAvatar)
        : (_qrDetail?.ownerThumbnail ?? currentPersonalOwner?.imageUrl);
    final avatarUrl = rawAvatar != null && rawAvatar.isNotEmpty
        ? resolveApiUrl(rawAvatar, apiBaseUrl)
        : null;

    final qrData = _qrDetail?.effectiveContent ?? '';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.isGroup ? '群二维码名片' : '我的二维码名片'),
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: '重置二维码',
            onPressed: _loading ? null : () => _loadQrCode(reset: true),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 20),
            tooltip: '复制链接',
            onPressed: qrData.isEmpty ? null : () => _copyQrLink(qrData),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 多 ChatObjectId 身份切换器
                  if (!widget.isGroup && owners.length > 1) ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: owners.map((o) {
                          final selected = o.id == _selectedOwnerId;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                o.typeDescription.isNotEmpty
                                    ? '${o.name} (${o.typeDescription})'
                                    : o.name,
                              ),
                              selected: selected,
                              onSelected: _loading
                                  ? null
                                  : (_) {
                                      setState(() => _selectedOwnerId = o.id);
                                      _loadQrCode();
                                    },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 有效期选择栏
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      if (!widget.isGroup)
                        ChoiceChip(
                          label: const Text('永久有效'),
                          selected: _isPermanent == true && _expireDays == null,
                          onSelected: _loading
                              ? null
                              : (_) => _selectValidity(
                                  isPermanent: true,
                                  expireDays: null,
                                ),
                        ),
                      ChoiceChip(
                        label: const Text('7天'),
                        selected: _isPermanent == false && _expireDays == 7,
                        onSelected: _loading
                            ? null
                            : (_) => _selectValidity(
                                isPermanent: false,
                                expireDays: 7,
                              ),
                      ),
                      ChoiceChip(
                        label: const Text('30天'),
                        selected: _isPermanent == false && _expireDays == 30,
                        onSelected: _loading
                            ? null
                            : (_) => _selectValidity(
                                isPermanent: false,
                                expireDays: 30,
                              ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.edit_calendar_rounded, size: 16),
                        label: Text(
                          (_expireDays != null &&
                                  _expireDays != 7 &&
                                  _expireDays != 30)
                              ? '$_expireDays天'
                              : '自定义天数',
                        ),
                        onPressed: _loading ? null : _promptCustomDays,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── 可保存截图的名片主体卡片 ──
                  RepaintBoundary(
                    key: _cardKey,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                      decoration: BoxDecoration(
                        color: isDark
                            ? colorScheme.surfaceContainerHigh
                            : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.3,
                          ),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.3 : 0.08,
                            ),
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
                              AppAvatar(
                                name: name,
                                imageUrl: avatarUrl,
                                radius: 26,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 17,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitle,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                    if (_selectedOwnerId != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '对象ID: $_selectedOwnerId',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
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
                            child: _loading
                                ? const CircularProgressIndicator()
                                : _error != null
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _error!,
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: colorScheme.error,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextButton(
                                        onPressed: () => _loadQrCode(),
                                        child: const Text('重试'),
                                      ),
                                    ],
                                  )
                                : qrData.isNotEmpty
                                ? QrImageView(
                                    data: qrData,
                                    version: QrVersions.auto,
                                    size: 200,
                                    backgroundColor: Colors.white,
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.isGroup
                                ? '扫一扫上面的二维码图案，加入群聊'
                                : '扫一扫上面的二维码图案，加我为好友',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatValidityLabel(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── 底部快捷操作按钮 ──
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading
                              ? null
                              : () => _loadQrCode(reset: true),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('重置'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: qrData.isEmpty
                              ? null
                              : () => _copyQrLink(qrData),
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('复制'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: (_isSaving || _qrDetail == null)
                              ? null
                              : _saveQrImageToGallery,
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
                          label: Text(_isSaving ? '保存中...' : '保存相册'),
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
