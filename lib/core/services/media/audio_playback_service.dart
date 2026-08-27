import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../config/app_environment.dart';

class AudioPlaybackService extends ChangeNotifier {
  AudioPlaybackService({
    required AppEnvironment environment,
    AudioPlayer? player,
  }) : _environment = environment,
       _player = player ?? AudioPlayer() {
    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      _playing = state == PlayerState.playing;
      notifyListeners();
    });
    _completionSubscription = _player.onPlayerComplete.listen((_) {
      _playing = false;
      _activeMessageId = null;
      notifyListeners();
    });
  }

  final AppEnvironment _environment;
  final AudioPlayer _player;
  final AudioPlayer _effectPlayer = AudioPlayer();
  late final StreamSubscription<PlayerState> _stateSubscription;
  late final StreamSubscription<void> _completionSubscription;
  String? _activeMessageId;
  bool _playing = false;
  Object? _error;

  String? get activeMessageId => _activeMessageId;
  bool get isPlaying => _playing;
  Object? get error => _error;

  bool isMessagePlaying(String messageId) =>
      _activeMessageId == messageId && _playing;

  Future<void> toggle({
    required String messageId,
    String? localPath,
    String? url,
    String? mimeType,
  }) async {
    _error = null;
    try {
      if (_activeMessageId == messageId) {
        if (_playing) {
          await _player.pause();
        } else {
          await _player.resume();
        }
        return;
      }
      await _player.stop();
      final source = _source(
        localPath: localPath,
        url: url,
        mimeType: mimeType,
      );
      _activeMessageId = messageId;
      notifyListeners();
      await _player.play(source);
    } catch (error) {
      _error = error;
      _playing = false;
      _activeMessageId = null;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stop() async {
    await _player.stop();
    _playing = false;
    _activeMessageId = null;
    notifyListeners();
  }

  Future<void> playSendEffect() async {
    try {
      await _effectPlayer.stop();
      await _effectPlayer.play(
        BytesSource(_buildSendEffect(), mimeType: 'audio/wav'),
        volume: 0.45,
      );
    } catch (error) {
      debugPrint('[sendSound][failed] error=$error');
    }
  }

  static Uint8List _buildSendEffect() {
    const sampleRate = 22050;
    const durationMs = 145;
    final sampleCount = sampleRate * durationMs ~/ 1000;
    final dataLength = sampleCount * 2;
    final bytes = ByteData(44 + dataLength);
    void ascii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        bytes.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    ascii(0, 'RIFF');
    bytes.setUint32(4, 36 + dataLength, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, dataLength, Endian.little);
    var phase = 0.0;
    for (var index = 0; index < sampleCount; index++) {
      final progress = index / sampleCount;
      final frequency = 900 + 1900 * progress * progress;
      phase += 2 * math.pi * frequency / sampleRate;
      final envelope =
          progress < 0.08
              ? progress / 0.08
              : math.pow(1 - progress, 1.8).toDouble();
      final sample = (math.sin(phase) * envelope * 15000).round();
      bytes.setInt16(44 + index * 2, sample, Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  Source _source({String? localPath, String? url, String? mimeType}) {
    if (localPath != null && localPath.isNotEmpty) {
      return DeviceFileSource(localPath, mimeType: mimeType);
    }
    final value = url?.trim() ?? '';
    if (value.isEmpty) throw StateError('语音文件地址为空。');
    final parsed = Uri.tryParse(value);
    final resolved =
        parsed?.hasScheme == true
            ? value
            : Uri.parse(_environment.apiBaseUrl).resolve(value).toString();
    return UrlSource(resolved, mimeType: mimeType);
  }

  @override
  void dispose() {
    unawaited(_stateSubscription.cancel());
    unawaited(_completionSubscription.cancel());
    unawaited(_player.dispose());
    unawaited(_effectPlayer.dispose());
    super.dispose();
  }
}

final audioPlaybackServiceProvider =
    ChangeNotifierProvider<AudioPlaybackService>((ref) {
      return AudioPlaybackService(
        environment: ref.watch(appEnvironmentProvider),
      );
    });
