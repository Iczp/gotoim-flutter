import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/announcement_providers.dart';
import '../../data/models/session_announcement.dart';
import 'announcement_detail_dialog.dart';

class PinnedAnnouncementBanner extends ConsumerStatefulWidget {
  const PinnedAnnouncementBanner({
    required this.sessionId,
    this.sessionTitle,
    this.canManage = false,
    super.key,
  });

  final String sessionId;
  final String? sessionTitle;
  final bool canManage;

  @override
  ConsumerState<PinnedAnnouncementBanner> createState() =>
      _PinnedAnnouncementBannerState();
}

class _PinnedAnnouncementBannerState
    extends ConsumerState<PinnedAnnouncementBanner> {
  static final Set<String> _poppedAnnouncementIds = <String>{};

  late PinnedAnnouncementController _controller;
  bool _popupFlowRunning = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    _controller = PinnedAnnouncementController(
      ref.read(announcementApiProvider),
      widget.sessionId,
    );
    _checkAndShowPopupQueue();
  }

  @override
  void didUpdateWidget(covariant PinnedAnnouncementBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _controller.dispose();
      _popupFlowRunning = false;
      _initController();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkAndShowPopupQueue() async {
    if (_popupFlowRunning || widget.sessionId.isEmpty) return;
    _popupFlowRunning = true;
    try {
      final api = ref.read(announcementApiProvider);
      final results = await Future.wait([
        api.getPinned(widget.sessionId),
        api.getList(sessionId: widget.sessionId, maxResultCount: 50),
      ]);
      if (!mounted) return;

      final pinned = results[0] as SessionAnnouncement?;
      final list = results[1] as List<SessionAnnouncement>;

      final queue = <SessionAnnouncement>[];
      final seen = <String>{};
      if (pinned != null &&
          pinned.isPopup &&
          !pinned.isSelfConfirmed &&
          !_poppedAnnouncementIds.contains(pinned.id)) {
        queue.add(pinned);
        seen.add(pinned.id);
      }
      for (final item in list) {
        if (item.isPopup &&
            !item.isSelfConfirmed &&
            !_poppedAnnouncementIds.contains(item.id) &&
            seen.add(item.id)) {
          queue.add(item);
        }
      }

      for (final item in queue) {
        if (!mounted) break;
        if (_poppedAnnouncementIds.contains(item.id)) continue;
        _poppedAnnouncementIds.add(item.id);
        final detail = item.content.isNotEmpty
            ? item
            : await api.getDetail(item.id);
        if (!mounted || detail == null) continue;
        final confirmed = await AnnouncementDetailDialog.show(
          context,
          announcement: detail,
          sessionTitle: widget.sessionTitle,
          canManage: widget.canManage,
        );
        if (confirmed == true && mounted) {
          await _controller.refresh();
        }
      }
    } catch (_) {
      // ignore popup load failure
    } finally {
      _popupFlowRunning = false;
    }
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

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B).withValues(alpha: 0.62)
                      : const Color(0xFFFFFBEB).withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.16)
                        : Colors.orange.withValues(alpha: 0.28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.campaign, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
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
                        onTap: () async {
                          final confirmed = await AnnouncementDetailDialog.show(
                            context,
                            announcement: item,
                            sessionTitle: widget.sessionTitle,
                            canManage: widget.canManage,
                          );
                          if (confirmed == true && mounted) {
                            await _controller.refresh();
                          }
                        },
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ),
                    if (item.requireConfirm && !item.isSelfConfirmed) ...[
                      const SizedBox(width: 6),
                      SizedBox(
                        height: 24,
                        child: FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                          onPressed: _controller.confirm,
                          child: const Text('确认收到'),
                        ),
                      ),
                    ],
                    IconButton(
                      icon: const Icon(Icons.close, size: 15),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      tooltip: '隐藏横幅',
                      onPressed: _controller.dismiss,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
