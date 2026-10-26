import '../localization/app_localization.dart';
import 'package:flutter/material.dart';
import '../native_window/desktop_window_title_bar.dart';
import '../platform/desktop_window_adapter.dart';

/// Opaque, usable first frame while the local application services initialize.
class DesktopStartupScene extends StatelessWidget {
  const DesktopStartupScene({
    this.status,
    this.message = '正在准备工作区…',
    this.actions,
    super.key,
  });
  final ValueNotifier<String>? status;
  final String message;
  final Widget? actions;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: AppLocalization.locale,
    supportedLocales: AppLocalization.supportedLocales,
    localizationsDelegates: AppLocalization.delegates,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF07A86A),
      useMaterial3: true,
    ),
    home: Scaffold(
      backgroundColor: const Color(0xFFF3F7F5),
      body: Column(
        children: [
          DesktopWindowTitleBar(
            title: 'Goto IM',
            showPin: false,
            backgroundColor: const Color(0xFFF3F7F5),
            onClose: DesktopWindowAdapter.close,
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: const Color(0xFF07A86A),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Icon(
                          Icons.forum_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Goto IM',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '让每一次沟通，即刻连接',
                        style: TextStyle(
                          color: Color(0xFF64746D),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 36),
                      const SizedBox(
                        width: 190,
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                      const SizedBox(height: 16),
                      if (status != null)
                        ValueListenableBuilder<String>(
                          valueListenable: status!,
                          builder:
                              (_, value, _) => Text(
                                value,
                                style: const TextStyle(
                                  color: Color(0xFF64746D),
                                ),
                              ),
                        )
                      else
                        Text(message),
                      const SizedBox(height: 12),
                      if (actions != null) ...[
                        const SizedBox(height: 16),
                        actions!,
                      ],
                      const Text(
                        '本地消息正在准备，连接服务后自动同步',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF8A9891),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'GOTO IM · 即时沟通',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                color: Color(0xFF8A9891),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
