import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/social_publish_controller.dart';
import '../application/social_profile_preview.dart';
import '../application/social_identity_controller.dart';
import '../data/social_repository.dart';

class SocialPublishPage extends ConsumerStatefulWidget {
  const SocialPublishPage({super.key});
  @override
  ConsumerState<SocialPublishPage> createState() => _SocialPublishPageState();
}

class _SocialPublishPageState extends ConsumerState<SocialPublishPage> {
  final _text = TextEditingController();
  late final SocialPublishController _controller;
  int _visibility = 0;
  @override
  void initState() {
    super.initState();
    _controller = SocialPublishController(
      ref.read(socialRepositoryProvider),
      actor: ref.read(socialIdentityProvider).actor,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final result = await _controller.publish(
      _text.text,
      visibility: _visibility,
    );
    if (result != null && mounted) {
      ref.invalidate(socialProfilePreviewProvider);
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder:
        (context, _) => PopScope(
          canPop: !_controller.submitting,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('发布动态'),
              actions: [
                TextButton(
                  onPressed: _controller.submitting ? null : _publish,
                  child: Text(_controller.submitting ? '发布中…' : '发布'),
                ),
              ],
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      controller: _text,
                      enabled: !_controller.submitting,
                      minLines: 6,
                      maxLines: 14,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        hintText: '分享新鲜事，支持 #话题 和 @提及',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: _visibility,
                      decoration: const InputDecoration(labelText: '谁可以看'),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('公开')),
                        DropdownMenuItem(value: 1, child: Text('关注者')),
                        DropdownMenuItem(value: 3, child: Text('仅自己')),
                      ],
                      onChanged:
                          _controller.submitting
                              ? null
                              : (value) {
                                if (value != null) {
                                  setState(() => _visibility = value);
                                }
                              },
                    ),
                    if (_controller.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          _controller.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text('当前支持文字动态。网络失败时重试相同内容会复用发布编号，避免重复发布。'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
  );
}
