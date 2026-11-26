import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/application_providers.dart';
import '../../application/announcement_providers.dart';
import '../../data/models/session_announcement.dart';
import 'announcement_detail_dialog.dart';

class PinnedAnnouncementBanner extends ConsumerStatefulWidget {
  const PinnedAnnouncementBanner({
    required this.sessionId,
    this.sessionUnitId,
    this.sessionTitle,
    this.canManage = false,
    this.refreshTriggerKey,
    super.key,
  });

  final String sessionId;
  final String? sessionUnitId;
  final String? sessionTitle;
  final bool canManage;
  final String? refreshTriggerKey;

  @override
  ConsumerState<PinnedAnnouncementBanner> createState() =>
      _PinnedAnnouncementBannerState();
}

class _PinnedAnnouncementBannerState
    extends ConsumerState<PinnedAnnouncementBanner> {
  static final Set<String> _poppedAnnouncementIds = <String>{};

  late PinnedAnnouncementController _controller;
  bool _popupFlowRunning = false;

  String get _effectiveSessionUnitId =>
      (widget.sessionUnitId != null && widget.sessionUnitId!.isNotEmpty)
          ? widget.sessionUnitId!
          : widget.sessionId;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    _controller = PinnedAnnouncementController(
      ref.read(announcementApiProvider),
      widget.sessionId,
      sessionUnitId: widget.sessionUnitId,
      database: ref.read(unifiedDatabaseProvider),
    );
    _checkAndShowPopupQueue();
  }

  @override
  void didUpdateWidget(covariant PinnedAnnouncementBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.sessionUnitId != widget.sessionUnitId) {
      _controller.dispose();
      _popupFlowRunning = false;
      _initController();
    } else if (oldWidget.refreshTriggerKey != widget.refreshTriggerKey &&
        widget.refreshTriggerKey != null &&
        widget.refreshTriggerKey!.isNotEmpty) {
      _controller.loadPinned();
      _checkAndShowPopupQueue();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkAndShowPopupQueue() async {
    final uid = _effectiveSessionUnitId;
    if (_popupFlowRunning || uid.isEmpty) return;
    _popupFlowRunning = true;
    try {
      await _controller.ensureDismissedLoaded();
      final api = ref.read(announcementApiProvider);
      final results = await Future.wait([
        api.getPinned(uid),
        api.getList(sessionUnitId: uid, maxResultCount: 50),
      ]);
      if (!mounted) return;

      final pinned = results[0] as SessionAnnouncement?;
      final list = results[1] as List<SessionAnnouncement>;

      final queue = <SessionAnnouncement>[];
      final seen = <String>{};
      bool isEligiblePopup(SessionAnnouncement item) {
        final popupKey = '${item.id}:${item.version}';
        return item.isPopup &&
            !item.isSelfConfirmed &&
            !item.isExpired &&
            item.isEffectiveForCurrentUser &&
            !_controller.isDismissedItem(item) &&
            !_poppedAnnouncementIds.contains(popupKey);
      }

      if (pinned != null && isEligiblePopup(pinned)) {
        queue.add(pinned);
        seen.add(pinned.id);
      }
      for (final item in list) {
        if (queue.length >= 3) break;
        if (isEligiblePopup(item) && seen.add(item.id)) {
          queue.add(item);
        }
      }

      for (final item in queue) {
        if (!mounted) break;
        final popupKey = '${item.id}:${item.version}';
        if (_poppedAnnouncementIds.contains(popupKey)) continue;
        _poppedAnnouncementIds.add(popupKey);
        final detail = item.content.isNotEmpty
            ? item
            : await api.getDetail(item.id, sessionUnitId: uid);
        if (!mounted || detail == null) continue;
        final confirmed = await AnnouncementDetailDialog.show(
          context,
          announcement: detail,
          sessionUnitId: uid,
          sessionTitle: widget.sessionTitle,
          canManage: widget.canManage,
        );
        if (!mounted) continue;
        if (confirmed == true) {
          await _controller.markViewed(item.copyWith(isSelfConfirmed: true));
        } else if (!item.requireConfirm) {
          await _controller.markViewed(item);
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
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                    const Icon(Icons.campaign, color: Colors.orange, size: 17),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                    const SizedBox(width: 6),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final confirmed = await AnnouncementDetailDialog.show(
                            context,
                            announcement: item,
                            sessionUnitId: _effectiveSessionUnitId,
                            sessionTitle: widget.sessionTitle,
                            canManage: widget.canManage,
                          );
                          if (!mounted) return;
                          if (confirmed == true) {
                            await _controller.markViewed(
                              item.copyWith(isSelfConfirmed: true),
                            );
                          } else if (!item.requireConfirm) {
                            await _controller.markViewed(item);
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
                    if (_controller.pinnedList.length > 1) ...[
                      IconButton(
                        icon: const Icon(Icons.chevron_left, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _controller.prevPinned,
                      ),
                      Text(
                        '${_controller.pinnedIndex + 1}/${_controller.pinnedList.length}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _controller.nextPinned,
                      ),
                    ],
                    if (item.requireConfirm && !item.isSelfConfirmed) ...[
                      const SizedBox(width: 6),
                      SizedBox(
                        height: 22,
                        child: FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 9),
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
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
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
