import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/file/attachment_transfer_service.dart';
import '../../application/chat_controller.dart';

/// Enforces online authorization (`POST /api/chat/file/sign`) before rendering
/// private `/api/chat/file/{blobId}` images, video covers, or local cached files.
///
/// Fails closed when recalled/deleted locally, denied by the server, offline,
/// or when no [AttachmentTransferService] is available for a private attachment.
class AuthorizedPrivateAttachmentGate extends StatefulWidget {
  const AuthorizedPrivateAttachmentGate({
    required this.url,
    required this.apiBaseUrl,
    required this.builder,
    this.accessContext,
    this.userId,
    this.isBlockedLocally = false,
    this.transferService,
    this.onAuthorizationChanged,
    this.deniedBuilder,
    this.loadingBuilder,
    super.key,
  });

  final String url;
  final String apiBaseUrl;
  final AttachmentAccessContext? accessContext;
  final String? userId;
  final bool isBlockedLocally;
  final AttachmentTransferService? transferService;
  final ValueChanged<bool>? onAuthorizationChanged;
  final WidgetBuilder builder;
  final WidgetBuilder? deniedBuilder;
  final WidgetBuilder? loadingBuilder;

  @override
  State<AuthorizedPrivateAttachmentGate> createState() =>
      _AuthorizedPrivateAttachmentGateState();
}

class _AuthorizedPrivateAttachmentGateState
    extends State<AuthorizedPrivateAttachmentGate> {
  AttachmentTransferService? _listeningService;
  int _lastObservedRevision = -1;
  int _requestGeneration = 0;
  bool? _authorized;

  bool get _isProtected => AttachmentTransferService.isProtectedChatAttachmentUrl(
    widget.url,
    widget.apiBaseUrl,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncServiceAndVerify();
  }

  @override
  void didUpdateWidget(covariant AuthorizedPrivateAttachmentGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contextChanged =
        oldWidget.url != widget.url ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl ||
        oldWidget.userId != widget.userId ||
        oldWidget.isBlockedLocally != widget.isBlockedLocally ||
        oldWidget.transferService != widget.transferService ||
        oldWidget.accessContext?.sessionUnitId !=
            widget.accessContext?.sessionUnitId ||
        oldWidget.accessContext?.messageId != widget.accessContext?.messageId ||
        oldWidget.accessContext?.rootMessageId !=
            widget.accessContext?.rootMessageId;
    if (contextChanged) {
      _syncServiceAndVerify(forceRecheck: true);
    }
  }

  @override
  void dispose() {
    _listeningService?.removeListener(_handleServiceChanged);
    _listeningService = null;
    super.dispose();
  }

  AttachmentTransferService? _resolveTransferService() {
    if (widget.transferService != null) return widget.transferService;
    try {
      return ProviderScope.containerOf(
        context,
        listen: false,
      ).read(attachmentTransferServiceProvider);
    } catch (_) {
      return null;
    }
  }

  void _handleServiceChanged() {
    final service = _listeningService;
    if (service == null) return;
    if (service.accessRevision != _lastObservedRevision) {
      _lastObservedRevision = service.accessRevision;
      unawaited(_verifyOnline(service, forceReset: true));
    }
  }

  void _syncServiceAndVerify({bool forceReset = false, bool forceRecheck = false}) {
    final service = _resolveTransferService();
    if (!identical(_listeningService, service)) {
      _listeningService?.removeListener(_handleServiceChanged);
      _listeningService = service;
      if (service != null) {
        _lastObservedRevision = service.accessRevision;
        service.addListener(_handleServiceChanged);
      } else {
        _lastObservedRevision = -1;
      }
      forceRecheck = true;
    }

    if (widget.isBlockedLocally) {
      _requestGeneration++;
      _setAuthorized(false);
      return;
    }

    if (!_isProtected) {
      _requestGeneration++;
      _setAuthorized(true);
      return;
    }

    if (service == null) {
      _requestGeneration++;
      _setAuthorized(false);
      return;
    }

    if (forceReset || forceRecheck || _authorized == null) {
      unawaited(_verifyOnline(service, forceReset: forceReset));
    }
  }

  Future<void> _verifyOnline(
    AttachmentTransferService service, {
    bool forceReset = false,
  }) async {
    final generation = ++_requestGeneration;
    if (forceReset && mounted && _authorized != null) {
      _setAuthorized(null);
    }
    final allowed = await service.authorizePrivateAttachment(
      widget.url,
      accessContext: widget.accessContext,
      userId: widget.userId,
    );
    if (!mounted || generation != _requestGeneration) return;
    _setAuthorized(allowed);
  }

  void _setAuthorized(bool? value) {
    final previous = _authorized;
    if (previous != value) {
      if (mounted) {
        setState(() => _authorized = value);
      } else {
        _authorized = value;
      }
      if (value != null) {
        widget.onAuthorizationChanged?.call(value);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isBlockedLocally) {
      return widget.deniedBuilder?.call(context) ??
          const _DefaultDeniedMediaPlaceholder();
    }
    if (!_isProtected) {
      return widget.builder(context);
    }
    return switch (_authorized) {
      true => widget.builder(context),
      false =>
        widget.deniedBuilder?.call(context) ??
            const _DefaultDeniedMediaPlaceholder(),
      null =>
        widget.loadingBuilder?.call(context) ??
            const Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
    };
  }
}

class _DefaultDeniedMediaPlaceholder extends StatelessWidget {
  const _DefaultDeniedMediaPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.lock_outline,
          size: 28,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
