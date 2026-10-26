import 'package:desktop_multi_window/desktop_multi_window.dart';
// Native Windows smoke entrypoint. Build its asset bundle into a separate
// output directory; never replace a running development application's bundle.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gotoim_flutter/app/app_navigation.dart';
import 'package:gotoim_flutter/core/browser/desktop_browser_dock_controller.dart';
import 'package:gotoim_flutter/core/native_window/native_sub_window_app.dart';
import 'package:gotoim_flutter/core/native_window/desktop_dock_slot.dart';
import 'package:gotoim_flutter/core/media/media_preview.dart';
import 'package:gotoim_flutter/core/platform/platform_facade.dart';
import 'package:gotoim_flutter/core/platform/windows/windows_window_adapter.dart';
import 'package:gotoim_flutter/core/services/window_service.dart';

Size? _lastMainLayout;
double _mainScale = 1;

class _SmokeWindows extends DefaultWindowService {
  _SmokeWindows() : super(platformFacade: createPlatformFacade());
  // Avoid repeated focus requests while exercising the native test windows.
  @override
  Future<void> bringToFront(String targetId) async {}
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == 'multi_window') {
    await runNativeSubWindowApp(args);
    return;
  }
  final resultPath = args
      .firstWhere((arg) => arg.startsWith('--result='))
      .substring(9);
  void phase(String value) => File(
    '$resultPath.progress',
  ).writeAsStringSync('$value\n', mode: FileMode.append);
  phase('main entered');
  WidgetsFlutterBinding.ensureInitialized();
  phase('binding ready');
  final loads = <String, int>{};
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  phase('HTTP server ready');
  final subscription = server.listen((request) async {
    final path = request.uri.path;
    if (path == '/a' || path == '/b') {
      loads.update(path, (count) => count + 1, ifAbsent: () => 1);
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '''<!doctype html><title>Probe $path</title>
        <style>body{background:#edf8f2;font:18px system-ui;padding:24px}input{padding:12px}</style>
        <h2>Live browser resize probe</h2><p id="dimensions"></p>
        <input id="probe" value="unsent form">
        <script>function dimensions(){document.querySelector('#dimensions').textContent=innerWidth+' x '+innerHeight;}
        addEventListener('resize',dimensions);dimensions();</script>
        <script>window.__gotoimDockProbe = String(Date.now()) + Math.random();</script>''',
      );
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  });
  final service = _SmokeWindows();
  phase('window service ready');
  final container = ProviderContainer(
    overrides: [windowServiceProvider.overrideWithValue(service)],
  );
  rootProviderContainer = container;
  final results = <Map<String, dynamic>>[];
  Object? failure;
  try {
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const _ProbeShell(),
      ),
    );
    phase('runApp called');
    // A hidden Windows surface may not deliver layout frames. Rendering this
    // isolated test copy is required for real native view/resize assertions.
    await WindowsWindowAdapter.bringToFront();
    phase('native host shown');
    await WidgetsBinding.instance.endOfFrame.timeout(
      const Duration(seconds: 10),
    );
    phase('first frame ready');
    final notifier = container.read(desktopBrowserDockProvider.notifier);
    service.onWindowDockLayoutRequested =
        (_) => WidgetsBinding.instance.endOfFrame;
    final url = 'http://127.0.0.1:${server.port}';
    await notifier.requestDock(url: '$url/a', title: 'Probe A');
    results.add(await _ready(service, 1));
    await notifier.requestDock(url: '$url/b', title: 'Probe B');
    final baseline = await _ready(service, 2);
    results.add(baseline);
    final session = baseline['session'] as Map;
    final marker = (session['pageProbe'] as Map)['marker'];
    final host = (baseline['native'] as Map)['windowHwnd'];
    _check(
      ((baseline['native'] as Map)['preparedFrameCount'] as num? ?? 0) > 0,
      'Browser was exposed before native frame preparation',
    );
    for (var iteration = 0; iteration < 4; iteration++) {
      await notifier.requestUndock(showWindow: true);
      final detached = await _ready(service, 2);
      results.add(detached);
      final detachedNative = detached['native'] as Map;
      if (iteration == 0 && args.contains('--inspect-detached')) {
        phase('visible pop-out ready for inspection');
        final deadline = Stopwatch()..start();
        while (!File('$resultPath.resume').existsSync() &&
            deadline.elapsed < const Duration(seconds: 180)) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
      if (iteration == 0 && args.contains('--inspect-detached')) {
        final afterResize = await _ready(service, 2);
        results.add({
          'afterLiveResize': afterResize,
          'mainResize': await WindowsWindowAdapter.browserDockDiagnostics(),
          'mainLayout': {
            'width': _lastMainLayout?.width,
            'height': _lastMainLayout?.height,
            'scale': _mainScale,
          },
        });
        final nativeSize = afterResize['native'] as Map;
        _check(
          nativeSize['clientWidth'] == nativeSize['contentWidth'] &&
              nativeSize['clientHeight'] == nativeSize['contentHeight'],
          'Flutter native surface did not catch up to the final browser size',
        );
        _check(
          (nativeSize['resizeGestures'] as num? ?? 0) > 0,
          'Browser live resize was not actually exercised',
        );
        final page = afterResize['session']['pageProbe'] as Map;
        final viewWidth = afterResize['session']['flutterViewWidth'] as num;
        _check(
          ((page['innerWidth'] as num) - viewWidth).abs() <= 1,
          'Browser DOM viewport is stale after resize',
        );
        final mainSize = await WindowsWindowAdapter.browserDockDiagnostics();
        _check(
          (mainSize['resizeGestures'] as num? ?? 0) > 0,
          'Main live resize was not actually exercised',
        );
        _check(
          _lastMainLayout != null &&
              (_lastMainLayout!.width * _mainScale -
                          (mainSize['clientWidth'] as num))
                      .abs() <=
                  1 &&
              (_lastMainLayout!.height * _mainScale -
                          (mainSize['clientHeight'] as num))
                      .abs() <=
                  1,
          'Main Flutter layout has not caught up to the native viewport',
        );
        _check(
          mainSize['clientWidth'] == mainSize['contentWidth'] &&
              mainSize['clientHeight'] == mainSize['contentHeight'],
          'Flutter main surface did not catch up to the final main size',
        );
      }
      _check(
        detachedNative['isDocked'] == false,
        'Browser is still docked after pop-out',
      );
      _check(
        detachedNative['windowHwnd'] == host,
        'Pop-out replaced the native browser',
      );
      _check(
        (detached['session']['pageProbe'] as Map)['marker'] == marker,
        'Visible pop-out reset JavaScript memory',
      );
      await WindowsWindowAdapter.center(
        width: 1100 + iteration * 40,
        height: 760,
      );
      await notifier.requestDock();
      final snapshot = await _ready(service, 2);
      results.add(snapshot);
      final native = snapshot['native'] as Map;
      final current = snapshot['session'] as Map;
      _check(native['windowHwnd'] == host, 'Native browser HWND changed');
      _check(
        (current['pageProbe'] as Map)['marker'] == marker,
        'JavaScript memory was reset',
      );
      _check(
        jsonEncode(current['tabIds']) == jsonEncode(session['tabIds']),
        'Tab identity changed',
      );
      _check(
        (current['creationCounts'] as List).every((count) => count == 1),
        'WebView recreated',
      );
      _check(
        native['mainThread'] == native['windowThread'],
        'Unexpected platform thread ownership',
      );
    }
    final videoArgs = args.where((arg) => arg.startsWith('--video='));
    final isVideo = videoArgs.isNotEmpty;
    final mediaFile =
        isVideo
            ? File(videoArgs.first.substring(8))
            : File('${File(resultPath).parent.path}/dock-probe.png');
    if (!isVideo) {
      await mediaFile.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
        ),
      );
    }
    await service.openMediaViewer(
      mediaUrl: mediaFile.path,
      items: [
        MediaPreviewItem(
          id: 'probe',
          heroTag: 'dock-probe',
          messageId: 'probe',
          type: isVideo ? MediaPreviewType.video : MediaPreviewType.image,
          source: mediaFile.path,
          localPath: mediaFile.path,
        ),
      ],
    );
    await service.ensureDockWindowReady('tool:media');
    await service.dock(targetId: 'tool:media');
    final mediaBaseline = await _mediaReady(service, isVideo);
    results.add(mediaBaseline);
    _check(
      ((mediaBaseline['native'] as Map)['preparedFrameCount'] as num? ?? 0) > 0,
      'Media window was exposed before native frame preparation',
    );
    _check(
      (await service.inspectWindowDock('tool:browser'))['native']['isDocked'] ==
          false,
      'Old browser still docked',
    );
    for (var iteration = 0; iteration < 2; iteration++) {
      await service.undock(targetId: 'tool:media', showWindow: false);
      await service.dock(targetId: 'tool:media');
      final media = await _mediaReady(service, isVideo);
      results.add(media);
      _check(
        media['content']['instanceId'] ==
            mediaBaseline['content']['instanceId'],
        'Media widget recreated',
      );
      _check(
        media['native']['windowHwnd'] == mediaBaseline['native']['windowHwnd'],
        'Media HWND changed',
      );
      if (isVideo) {
        _check(
          media['content']['playerId'] == mediaBaseline['content']['playerId'],
          'Player recreated',
        );
        _check(
          media['content']['positionMs'] >=
              mediaBaseline['content']['positionMs'],
          'Video position reset',
        );
      }
    }
    await notifier.requestDock();
    final backToBrowser = await _ready(service, 2);
    results.add(backToBrowser);
    _check(
      backToBrowser['session']['pageProbe']['marker'] == marker,
      'Replacing media reset browser',
    );
    final rect = await WindowsWindowAdapter.getWindowRect();
    container.read(desktopWindowDockProvider.notifier).updateBounds(
      DesktopWindowDockNotifier.chatRight,
      (x: 0, y: 0, width: rect!['clientWidth']!, height: rect['clientHeight']!),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final edgeProbe = await service.inspectWindowDock('tool:browser');
    results.add(edgeProbe);
    final native = edgeProbe['native'] as Map;
    final outer = native['mainClientRect'] as Map;
    final inner = native['windowRect'] as Map;
    _check(
      inner['left'] > outer['left'] &&
          inner['top'] > outer['top'] &&
          inner['right'] < outer['right'] &&
          inner['bottom'] < outer['bottom'],
      'Dock window covers a main resize edge',
    );
    _check(
      jsonEncode(native['mainResizeHitTests']) == '[10,11,12,15]',
      'Main resize hit tests failed',
    );
    _check(loads['/a'] == 1 && loads['/b'] == 1, 'Pages reloaded: $loads');
  } catch (error, stack) {
    failure = '$error\n$stack';
  }
  final report = <String, dynamic>{
    'passed': failure == null,
    'error': failure?.toString(),
    'httpLoads': loads,
    'snapshots': results,
  };
  await File(
    resultPath,
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  // Some native engines stop replying once their surface is hidden/disposed.
  // Bound teardown and let process shutdown release any remaining test engines.
  try {
    await service.closeAllSubWindows().timeout(const Duration(seconds: 15));
  } catch (error) {
    report['cleanupNote'] =
        'Native teardown reply unavailable; test process shutdown releases engines: ${error.runtimeType}';
  }
  await server
      .close(force: true)
      .then<void>((_) {})
      .timeout(const Duration(seconds: 2), onTimeout: () {});
  await subscription
      .cancel()
      .then<void>((_) {})
      .timeout(const Duration(seconds: 2), onTimeout: () {});
  await File(
    resultPath,
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  exit(failure == null ? 0 : 1);
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<Map<String, dynamic>> _mediaReady(
  DefaultWindowService service,
  bool video,
) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < const Duration(seconds: 15)) {
    final value = await service.inspectWindowDock('tool:media');
    final content = value['content'] as Map?;
    if (video &&
        content?['initialized'] == true &&
        content?['playing'] != true) {
      await WindowController.fromWindowId(
        value['windowId'] as String,
      ).invokeMethod('media_play');
    }
    if (content != null &&
        content['instanceId'] != null &&
        (!video ||
            (content['playing'] == true &&
                (content['positionMs'] as int? ?? 0) > 0))) {
      return value;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('Media did not initialise');
}

Future<Map<String, dynamic>> _ready(
  DefaultWindowService service,
  int tabs,
) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < const Duration(seconds: 15)) {
    final result = await service.inspectBrowserSession();
    final session = result['session'] as Map?;
    final probe = session?['pageProbe'];
    if (session != null &&
        (session['tabIds'] as List).length == tabs &&
        probe is Map &&
        probe['readyState'] == 'complete' &&
        probe['url'] == (session['urls'] as List).last) {
      return result;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('Native WebView did not load');
}

class _ProbeShell extends ConsumerWidget {
  const _ProbeShell();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state =
        ref.watch(desktopWindowDockProvider)[DesktopWindowDockNotifier
            .chatRight] ??
        const DesktopWindowDockState();
    return MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => WindowsWindowAdapter.startDragging(),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _lastMainLayout = constraints.biggest;
                    _mainScale = View.of(context).devicePixelRatio;
                    return Center(
                      child: Text(
                        'Main resize probe\n${constraints.maxWidth.round()} x ${constraints.maxHeight.round()}',
                      ),
                    );
                  },
                ),
              ),
            ),
            if (state.shouldRenderPlaceholder)
              SizedBox(
                width: 520,
                child: const DesktopDockSlot(
                  slotId: DesktopWindowDockNotifier.chatRight,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
