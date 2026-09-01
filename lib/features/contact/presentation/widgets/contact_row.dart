import 'package:flutter/material.dart';

import '../../../session/presentation/chat_object_avatar.dart';
import '../../data/models/contact_group.dart';
import 'contacts_page_chrome.dart';

class ContactRow extends StatelessWidget {
  const ContactRow({
    required this.contact,
    required this.showDivider,
    required this.onTap,
    super.key,
  });

  final ContactEntry contact;
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
          ChatObjectAvatar(
            name: contact.displayName,
            imageUrl: contact.avatarUrl.isEmpty ? null : contact.avatarUrl,
            radius: 21,
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
