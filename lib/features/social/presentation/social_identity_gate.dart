import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/social_identity_controller.dart';

class SocialIdentityGate extends ConsumerStatefulWidget {
  const SocialIdentityGate({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<SocialIdentityGate> createState() => _SocialIdentityGateState();
}

class _SocialIdentityGateState extends ConsumerState<SocialIdentityGate> {
  SocialIdentityController? _requested;
  SocialIdentityController? _completed;
  DialogRoute<bool>? _dialogRoute;

  Future<void> _confirm(SocialIdentityController identity) async {
    if (_dialogRoute != null || !mounted) return;
    final route = DialogRoute<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('创建 Social 身份？'),
            content: Text(
              '聊天身份“${identity.name}”尚未创建社区身份。是否以该 ChatObject 创建？取消不会创建身份。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('暂不创建'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认创建'),
              ),
            ],
          ),
    );
    _dialogRoute = route;
    final accepted = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(route);
    if (identical(_dialogRoute, route)) _dialogRoute = null;
    if (!mounted ||
        !identical(ref.read(socialIdentityProvider), identity) ||
        accepted != true) {
      return;
    }
    await identity.enter(create: true);
    if (mounted) setState(() {});
  }

  Future<void> _enter(SocialIdentityController identity) async {
    final oldDialog = _dialogRoute;
    if (oldDialog?.isActive == true) {
      oldDialog!.navigator?.removeRoute(oldDialog, false);
      await Future<void>.delayed(Duration.zero);
    }
    if (!mounted || !identical(ref.read(socialIdentityProvider), identity)) {
      return;
    }
    await identity.enter();
    if (!mounted || !identical(ref.read(socialIdentityProvider), identity)) {
      return;
    }
    setState(() => _completed = identity);
    if (identity.actor == null && identity.error == null) {
      await _confirm(identity);
    }
  }

  @override
  void dispose() {
    final dialog = _dialogRoute;
    if (dialog?.isActive == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (dialog!.isActive) dialog.navigator?.removeRoute(dialog, false);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(socialIdentityProvider);
    if (identity.chatObjectId != null && !identical(_requested, identity)) {
      _requested = identity;
      Future.microtask(() {
        if (mounted) _enter(identity);
      });
    }
    if (identical(_completed, identity) &&
        !identity.loading &&
        identity.actor != null) {
      return KeyedSubtree(
        key: ValueKey('${identity.chatObjectId}:${identity.actor!.id}'),
        child: widget.child,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Social 社交')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (identity.loading ||
                  (identity.chatObjectId != null &&
                      !identical(_completed, identity)))
                const CircularProgressIndicator()
              else ...[
                Text(
                  identity.chatObjectId == null
                      ? '请先在主应用选择聊天身份。'
                      : identity.error ?? '“${identity.name}”尚未创建 Social 身份。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (identity.chatObjectId != null)
                  FilledButton(
                    onPressed:
                        identity.error != null
                            ? () => _enter(identity)
                            : () => _confirm(identity),
                    child: Text(identity.error != null ? '重试' : '创建 Social 身份'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
