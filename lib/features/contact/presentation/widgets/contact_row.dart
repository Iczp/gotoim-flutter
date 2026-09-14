import 'package:flutter/material.dart';

import '../../../session/presentation/chat_object_avatar.dart';
import '../../data/models/contact_group.dart';
import 'contacts_page_chrome.dart';

class ContactRow extends StatelessWidget {
  const ContactRow({
    required this.contact,
    required this.onlineDeviceTypes,
    required this.showDivider,
    required this.onTap,
    super.key,
  });

  final ContactEntry contact;
  final List<String> onlineDeviceTypes;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 16),
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              ChatObjectAvatar(
                name: contact.displayName,
                imageUrl: contact.avatarUrl.isEmpty ? null : contact.avatarUrl,
                radius: 21,
              ),
              if (onlineDeviceTypes.isNotEmpty)
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: _OnlineDeviceBadge(deviceTypes: onlineDeviceTypes),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: ContactsPageMetrics.rowExtent,
              alignment: Alignment.centerLeft,
              decoration:
                  showDivider
                      ? BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: .35),
                            width: .5,
                          ),
                        ),
                      )
                      : null,
              child: Text(
                contact.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _OnlineDeviceBadge extends StatelessWidget {
  const _OnlineDeviceBadge({required this.deviceTypes});

  final List<String> deviceTypes;

  @override
  Widget build(BuildContext context) {
    final type = deviceTypes.first.toLowerCase();
    final icon =
        type.contains('phone') || type.contains('mobile')
            ? Icons.smartphone_rounded
            : type.contains('web')
            ? Icons.language_rounded
            : Icons.desktop_windows_rounded;
    return Transform.rotate(
      angle: .785398,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.surface,
            width: 2,
          ),
        ),
        child: Transform.rotate(
          angle: -.785398,
          child: Icon(icon, size: 10, color: Colors.white),
        ),
      ),
    );
  }
}
