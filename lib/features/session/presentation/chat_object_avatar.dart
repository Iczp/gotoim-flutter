import '../../../core/widgets/app_avatar.dart';

export '../../../core/widgets/app_avatar.dart' show AppAvatar;

/// Backwards-compatible name for the shared application avatar.
@Deprecated('Use AppAvatar from core/widgets/app_avatar.dart instead.')
class ChatObjectAvatar extends AppAvatar {
  const ChatObjectAvatar({
    required super.name,
    required super.imageUrl,
    super.radius,
    super.key,
  });
}
