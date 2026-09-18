import 'package:flutter/material.dart';

import '../application/app_update_service.dart';
import '../data/models/app_version_dto.dart';

/// Modal dialog for presenting version upgrade notifications and progress.
class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    required this.version,
    required this.updateService,
    super.key,
  });

  final AppVersionDto version;
  final AppUpdateService updateService;

  static Future<void> show(
    BuildContext context, {
    required AppVersionDto version,
    required AppUpdateService updateService,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: !version.isForce,
      useRootNavigator: true,
      builder: (dialogContext) => AppUpdateDialog(
        version: version,
        updateService: updateService,
      ),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _progressText = '';
  String? _errorMessage;

  Future<void> _startUpdate() async {
    final pkgUrl = widget.version.pkgUrl;
    final pageUrl = widget.version.pageUrl;

    // If there is no APK package direct link, open landing/store page directly
    if (pkgUrl == null || pkgUrl.isEmpty) {
      if (pageUrl != null && pageUrl.isNotEmpty) {
        await widget.updateService.openPageUrl(pageUrl);
      }
      if (mounted && !widget.version.isForce) {
        Navigator.of(context).pop();
      }
      return;
    }

    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _progressText = '准备下载...';
    });

    try {
      await widget.updateService.downloadAndInstall(
        widget.version,
        onProgress: (received, total) {
          if (!mounted) return;
          if (total > 0) {
            final percentage = (received / total).clamp(0.0, 1.0);
            final mbReceived = (received / (1024 * 1024)).toStringAsFixed(1);
            final mbTotal = (total / (1024 * 1024)).toStringAsFixed(1);
            setState(() {
              _progress = percentage;
              _progressText = '${(percentage * 100).toStringAsFixed(0)}% ($mbReceived MB / $mbTotal MB)';
            });
          } else {
            final mbReceived = (received / (1024 * 1024)).toStringAsFixed(1);
            setState(() {
              _progress = 0.0;
              _progressText = '$mbReceived MB';
            });
          }
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _errorMessage = '下载失败，请点击重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final version = widget.version;

    return PopScope(
      canPop: !version.isForce && !_isDownloading,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        backgroundColor: colorScheme.surface,
        elevation: 8,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380, maxHeight: 520),
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Badge & Version
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primary,
                          colorScheme.primary.withValues(alpha: 0.75),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.system_update_alt_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '发现新版本',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: version.isForce
                                    ? colorScheme.errorContainer
                                    : colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                version.isForce ? '重要更新' : '推荐',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: version.isForce
                                      ? colorScheme.onErrorContainer
                                      : colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'v${version.version} (Build ${version.versionCode})',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Title
              if (version.title.isNotEmpty) ...[
                Text(
                  version.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Release Notes Box
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      version.content?.trim().isNotEmpty == true
                          ? version.content!.trim()
                          : '优化了多项体验与性能，建议立即更新。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.6,
                        color: colorScheme.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Downloading state vs Action Buttons
              if (_isDownloading) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '正在下载升级包...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          _progressText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ] else ...[
                if (_errorMessage != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                  ),
                ],
                Row(
                  children: [
                    if (!version.isForce) ...[
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('稍后提醒'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: version.isForce ? 1 : 1,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _startUpdate,
                        child: Text(_errorMessage != null ? '重试下载' : '立即升级'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
