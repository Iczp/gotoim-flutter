import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/online_device_badge.dart';
import '../application/friend_presence_store.dart';

export '../../../core/widgets/app_avatar.dart' show AppAvatar;

/// Shared ChatObject avatar. Presence is keyed by ChatObject destinationId.
class ChatObjectAvatar extends ConsumerWidget {
  const ChatObjectAvatar({
    required this.name,
    required this.imageUrl,
    this.radius = 24,
    this.size,
    this.chatObjectId,
    super.key,
  });

  final String name;
  final String? imageUrl;
  final double radius;
  final double? size;
  final int? chatObjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceTypes =
        chatObjectId == null
            ? const <String>[]
            : ref
                .watch(friendPresenceStoreProvider)
                .deviceTypesForChatObjectId(chatObjectId);
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        AppAvatar(name: name, imageUrl: imageUrl, radius: radius, size: size),
        if (deviceTypes.isNotEmpty)
          Positioned(
            right: -3,
            bottom: -3,
            child: OnlineDeviceBadge(deviceTypes: deviceTypes),
          ),
      ],
    );
  }
}
