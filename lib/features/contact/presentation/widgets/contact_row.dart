import 'package:flutter/material.dart';

import '../../../session/presentation/chat_object_avatar.dart';
import '../../data/models/contact_group.dart';
import 'contacts_page_chrome.dart';

class ContactRow extends StatelessWidget {
  const ContactRow({
    required this.contact,
    required this.showDivider,
    required this.onTap,
    this.isSelected = false,
    this.onDoubleTap,
    this.onSecondaryTapDown,
    this.onAvatarHover,
    this.onAvatarLeave,
    super.key,
  });

  final ContactEntry contact;
  final bool showDivider;
  final VoidCallback onTap;
  final bool isSelected;
  final VoidCallback? onDoubleTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final void Function(Rect rect, ContactEntry contact)? onAvatarHover;
  final VoidCallback? onAvatarLeave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeBg = isDark ? const Color(0x3307C160) : const Color(0x1F07C160);

    return Material(
      color: isSelected ? activeBg : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onSecondaryTapDown: onSecondaryTapDown,
        child: Row(
          children: <Widget>[
            const SizedBox(width: 16),
            Builder(
              builder: (avatarCtx) {
                return MouseRegion(
                  onEnter: (e) {
                    if (onAvatarHover != null) {
                      final box = avatarCtx.findRenderObject() as RenderBox?;
                      if (box != null && box.hasSize) {
                        final origin = box.localToGlobal(Offset.zero);
                        final rect = origin & box.size;
                        onAvatarHover!(rect, contact);
                      }
                    }
                  },
                  onExit: (_) => onAvatarLeave?.call(),
                  child: ChatObjectAvatar(
                    name: contact.displayName,
                    imageUrl:
                        contact.avatarUrl.isEmpty ? null : contact.avatarUrl,
                    radius: 21,
                    chatObjectId: contact.destinationId,
                  ),
                );
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: ContactsPageMetrics.rowExtent,
                alignment: Alignment.centerLeft,
                decoration:
                    showDivider && !isSelected
                        ? BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: theme.dividerColor.withValues(alpha: .35),
                              width: .5,
                            ),
                          ),
                        )
                        : null,
                child: Text(
                  contact.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
