import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../social/application/social_profile_preview.dart';
import '../../user/data/models/profile_subject.dart';
import '../../user/presentation/widgets/profile_social_preview.dart';

class SocialProfileDiagnosticsPage extends ConsumerStatefulWidget {
  const SocialProfileDiagnosticsPage({super.key});
  @override
  ConsumerState<SocialProfileDiagnosticsPage> createState() =>
      _SocialProfileDiagnosticsPageState();
}

class _SocialProfileDiagnosticsPageState
    extends ConsumerState<SocialProfileDiagnosticsPage> {
  final _chatId = TextEditingController(text: '1');

  ProfileSubject? _subject;
  String? _error;
  @override
  void dispose() {
    _chatId.dispose();

    super.dispose();
  }

  void _execute() {
    final id = int.tryParse(_chatId.text.trim());
    if (id == null || id <= 0) {
      setState(() => _error = '请填写有效的 ChatObject ID。');
      return;
    }
    final subject = ProfileSubject(
      kind: ProfileKind.friend,
      id: '$id',
      name: '资料卡预览',
      avatarUrl: '',
      raw: {
        'destination': {'id': id},
      },
    );
    ref.invalidate(
      socialProfilePreviewProvider(socialTargetForProfile(subject)),
    );
    setState(() {
      _subject = subject;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final subject = _subject;
    final result =
        subject == null
            ? null
            : ref.watch(
              socialProfilePreviewProvider(socialTargetForProfile(subject)),
            );
    final status =
        result == null
            ? '未执行'
            : result.when(
              data: (_) => '成功',
              error: (_, stack) => '失败',
              loading: () => '执行中',
            );
    return Scaffold(
      appBar: AppBar(title: const Text('资料卡最近三条动态')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '通过资料卡ChatObject 绑定的 Social 身份读取最近三条可见动态。不会按昵称猜测，也不会替目标聊天身份自动创建 Social 身份。\nAndroid/iOS/平板/Windows/macOS/Linux/Web：Flutter 控件可用，网络需可访问 Chat 与 Social 服务。',
          ),
          TextField(
            controller: _chatId,
            decoration: const InputDecoration(
              labelText: 'ChatObject ID（缺少账号时查询 Chat）',
            ),
            keyboardType: TextInputType.number,
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(onPressed: _execute, child: const Text('读取最近三条')),
              TextButton(
                onPressed: () {
                  _chatId.text = '1';

                  setState(() {
                    _subject = null;
                    _error = null;
                  });
                },
                child: const Text('恢复默认'),
              ),
              TextButton(
                onPressed:
                    result == null
                        ? null
                        : () => Clipboard.setData(
                          ClipboardData(
                            text: result.when(
                              data:
                                  (data) => jsonEncode({
                                    'actorId': data.actor?.id,
                                    'postIds':
                                        data.posts
                                            .map((post) => post.id)
                                            .toList(),
                                    'count': data.posts.length,
                                  }),
                              error: (error, stack) => '$error\n$stack',
                              loading: () => '执行中',
                            ),
                          ),
                        ),
                child: const Text('复制结果'),
              ),
            ],
          ),
          Text(status),
          if (_error != null) Text(_error!),
          if (subject != null) ProfileSocialPreview(subject: subject),
        ],
      ),
    );
  }
}
