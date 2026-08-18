import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/scan_login_controller.dart';

class ScanLoginConfirmationPage extends ConsumerStatefulWidget {
  const ScanLoginConfirmationPage({super.key, required this.scanText});

  final String scanText;

  @override
  ConsumerState<ScanLoginConfirmationPage> createState() =>
      _ScanLoginConfirmationPageState();
}

class _ScanLoginConfirmationPageState
    extends ConsumerState<ScanLoginConfirmationPage> {
  ScanLoginController get _controller =>
      ref.read(scanLoginControllerProvider(widget.scanText));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.load());
  }

  Future<bool> _onWillPop() async {
    await _controller.cancelIfNeeded();
    return true;
  }

  Future<void> _submit({required bool approved}) async {
    final success =
        approved ? await _controller.grant() : await _controller.reject();
    if (!mounted || !success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(approved ? 'Login approved' : 'Login rejected')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(scanLoginControllerProvider(widget.scanText));
    final request = controller.request;
    final theme = Theme.of(context);
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(title: const Text('Confirm login')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: controller.loading
                  ? const Center(child: CircularProgressIndicator())
                  : controller.error != null && request == null
                      ? _ErrorState(onRetry: _controller.load)
                      : request == null
                          ? const SizedBox.shrink()
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Icon(Icons.devices_outlined,
                                    size: 52, color: theme.colorScheme.primary),
                                const SizedBox(height: 20),
                                Text('Allow this device to log in?',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.headlineSmall),
                                const SizedBox(height: 20),
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _DeviceField(
                                            'App',
                                            request.device.appName ??
                                                'Unknown app'),
                                        _DeviceField(
                                            'Device',
                                            request.device.deviceInfo ??
                                                'Unknown device'),
                                        _DeviceField(
                                            'Client ID',
                                            request.device.clientId ??
                                                'Unknown'),
                                      ],
                                    ),
                                  ),
                                ),
                                if (controller.error != null) ...[
                                  const SizedBox(height: 12),
                                  Text(controller.error.toString(),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: theme.colorScheme.error)),
                                ],
                                const SizedBox(height: 24),
                                Row(children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: controller.submitting
                                          ? null
                                          : () => _submit(approved: false),
                                      child: const Text('Reject'),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: controller.submitting ||
                                              !request.canAuthorize
                                          ? null
                                          : () => _submit(approved: true),
                                      child: controller.submitting
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2))
                                          : const Text('Allow login'),
                                    ),
                                  ),
                                ]),
                              ],
                            ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceField extends StatelessWidget {
  const _DeviceField(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text('$label: $value'),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Unable to inspect this login request.'),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
}
