import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/announcement_providers.dart';
import 'announcement_detail_dialog.dart';

class PinnedAnnouncementBanner extends ConsumerStatefulWidget {
  const PinnedAnnouncementBanner({
    required this.sessionId,
    this.canManage = false,
    super.key,
  });

  final String sessionId;
  final bool canManage;

  @override
  ConsumerState<PinnedAnnouncementBanner> createState() =>
      _PinnedAnnouncementBannerState();
}

class _PinnedAnnouncementBannerState
    extends ConsumerState<PinnedAnnouncementBanner> {
  late PinnedAnnouncementController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PinnedAnnouncementController(
      ref.read(announcementApiProvider),
      widget.sessionId,
    );
  }

  @override
  void didUpdateWidget(covariant PinnedAnnouncementBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _controller.dispose();
      _controller = PinnedAnnouncementController(
        ref.read(announcementApiProvider),
        widget.sessionId,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sessionId.isEmpty) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final item = _controller.pinned;

        if (item == null || _controller.isDismissed) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2D2415) : const Color(0xFFFFFBEB),
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF4A3B1F) : const Color(0xFFFEF3C7),
              ),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.campaign, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '公告',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    AnnouncementDetailDialog.show(
                      context,
                      announcement: item,
                      canManage: widget.canManage,
                    );
                  },
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                    ),
                  ),
                ),
              ),
              if (item.requireConfirm && !item.isSelfConfirmed) ...[
                const SizedBox(width: 6),
                SizedBox(
                  height: 26,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                    onPressed: _controller.confirm,
                    child: const Text('确认收到'),
                  ),
                ),
              ],
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                onPressed: _controller.dismiss,
              ),
            ],
          ),
        );
      },
    );
  }
}
