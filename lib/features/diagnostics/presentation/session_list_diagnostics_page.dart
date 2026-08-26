import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/clipboard_service.dart';
import '../../session/application/session_list_controller.dart';

class SessionListDiagnosticsPage extends ConsumerWidget {
  const SessionListDiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(sessionListControllerProvider);
    final result = const JsonEncoder.withIndent('  ').convert({
      'ownerId': controller.currentOwner?.id,
      'ownerName': controller.currentOwner?.name,
      'ownerCount': controller.owners.length,
      'sessionCount': controller.sessions.length,
      'hasMore': controller.hasMore,
      'isLoading': controller.isLoading,
      'isRefreshing': controller.isRefreshing,
      'error': controller.error?.toString(),
      'cursor':
          controller.sessions.isEmpty
              ? null
              : {
                'id': controller.sessions.last.id,
                'score': controller.sessions.last.score,
              },
      'maxTicks': controller.sessions.fold<int>(
        0,
        (value, item) => item.ticks > value ? item.ticks : value,
      ),
      'avatarCache': {
        'native': '系统应用缓存目录（flutter_cache_manager/libCachedImageData）',
        'web': '不写本地文件，使用网络图片',
        'envPathConfigured': false,
        'relativeUrlBase': 'API_BASE_URL',
      },
    });
    return Scaffold(
      appBar: AppBar(title: const Text('消息列表诊断')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('功能：Owner、Drift 本地分页、线上补页与 changes 增量刷新。'),
          const SizedBox(height: 8),
          const Text('支持：Android/iOS/iPad/Windows/macOS/Linux/Web'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: controller.isLoading ? null : controller.initialize,
                child: const Text('初始化'),
              ),
              OutlinedButton(
                onPressed:
                    controller.currentOwner == null
                        ? null
                        : controller.loadNextPage,
                child: const Text('加载下一页'),
              ),
              OutlinedButton(
                onPressed:
                    controller.currentOwner == null
                        ? null
                        : controller.refreshChanges,
                child: const Text('刷新变更'),
              ),
              OutlinedButton.icon(
                onPressed:
                    () => ref.read(clipboardServiceProvider).copy(result),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('复制输出'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SelectableText(result),
        ],
      ),
    );
  }
}
