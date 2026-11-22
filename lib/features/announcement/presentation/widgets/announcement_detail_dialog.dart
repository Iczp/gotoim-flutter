import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/session_announcement.dart';
import '../../application/announcement_providers.dart';
import '../announcement_stat_sheet.dart';

class AnnouncementDetailDialog extends ConsumerStatefulWidget {
  const AnnouncementDetailDialog({
    required this.announcement,
    this.canManage = false,
    super.key,
  });

  final SessionAnnouncement announcement;
  final bool canManage;

  static Future<void> show(
    BuildContext context, {
    required SessionAnnouncement announcement,
    bool canManage = false,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => AnnouncementDetailDialog(
        announcement: announcement,
        canManage: canManage,
      ),
    );
  }

  @override
  ConsumerState<AnnouncementDetailDialog> createState() =>
      _AnnouncementDetailDialogState();
}

class _AnnouncementDetailDialogState
    extends ConsumerState<AnnouncementDetailDialog> {
  late SessionAnnouncement _item;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _item = widget.announcement;
    // 自动上报已读
    ref.read(announcementApiProvider).recordView(_item.id);
  }

  Future<void> _handleConfirm() async {
    setState(() => _confirming = true);
    try {
      await ref.read(announcementApiProvider).confirm(_item.id);
      if (mounted) {
        setState(() {
          _item = _item.copyWith(
            isSelfConfirmed: true,
            confirmedCount: _item.confirmedCount + 1,
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已确认收到公告')),
        );
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  void _openStat() {
    Navigator.of(context).pop();
    AnnouncementStatSheet.show(
      context,
      announcementId: _item.id,
      title: _item.title,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (_item.isPinned) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '置顶',
                        style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      _item.title,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '发布人: ${_item.publisherName ?? "管理员"}',
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    _item.creationTime.length > 16
                        ? _item.creationTime.substring(0, 16).replaceAll('T', ' ')
                        : _item.creationTime,
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                  ),
                ],
              ),
              const Divider(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    _item.content,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                  ),
                ),
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '已读 ${_item.readCount} 人'
                    '${_item.requireConfirm ? " · 已确认 ${_item.confirmedCount} 人" : ""}',
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                  ),
                  Row(
                    children: [
                      if (widget.canManage)
                        TextButton.icon(
                          icon: const Icon(Icons.pie_chart_outline, size: 16),
                          label: const Text('统计'),
                          onPressed: _openStat,
                        ),
                      if (_item.requireConfirm) ...[
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.check_circle_outline, size: 16),
                          label: Text(_item.isSelfConfirmed ? '已确认' : '确认收到'),
                          onPressed: _item.isSelfConfirmed || _confirming ? null : _handleConfirm,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
