import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../config/app_environment.dart';
import '../../native/sensor.dart';
import 'voice_cache_service.dart';

class AudioPlaybackService extends ChangeNotifier {
  AudioPlaybackService({
    required AppEnvironment environment,
    required VoiceCacheService voiceCacheService,
    required NativeSensor nativeSensor,
    AudioPlayer? player,
  }) : _environment = environment,
       _voiceCacheService = voiceCacheService,
       _player = player ?? AudioPlayer() {
    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      _playing = state == PlayerState.playing;
      notifyListeners();
    });
    _completionSubscription = _player.onPlayerComplete.listen((_) {
      _playing = false;
      _activeMessageId = null;
      _manualEarpiece = false;
      unawaited(setEarpiece(false));
      notifyListeners();
    });
    _proximitySubscription = nativeSensor.onProximityChange.listen((event) {
      if (_playing && !_manualEarpiece) {
        unawaited(setEarpiece(event.isNear));
      }
    });
    _positionSubscription = _player.onPositionChanged.listen((value) {
      _position = value;
      notifyListeners();
    });
    _durationSubscription = _player.onDurationChanged.listen((value) {
      _duration = value;
      notifyListeners();
    });
  }

  final AppEnvironment _environment;
  final VoiceCacheService _voiceCacheService;
  final AudioPlayer _player;
  final AudioPlayer _effectPlayer = AudioPlayer();
  late final StreamSubscription<PlayerState> _stateSubscription;
  late final StreamSubscription<void> _completionSubscription;
  late final StreamSubscription<ProximityEvent> _proximitySubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<Duration> _durationSubscription;
  String? _activeMessageId;
  bool _playing = false;
  Object? _error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _downloadingMessageId;
  double _downloadProgress = 0;
  bool _earpiece = false;
  bool _manualEarpiece = false;
  int _operation = 0;

  String? get activeMessageId => _activeMessageId;
  bool get isPlaying => _playing;
  Object? get error => _error;
  Duration get position => _position;
  Duration get duration => _duration;
  String? get downloadingMessageId => _downloadingMessageId;
  double get downloadProgress => _downloadProgress;
  bool get isEarpiece => _earpiece;
  bool get isManualEarpiece => _manualEarpiece;

  bool isMessagePlaying(String messageId) =>
      _activeMessageId == messageId && _playing;

  Future<void> toggle({
    required String messageId,
    String? localPath,
    String? url,
    String? mimeType,
  }) async {
    final operation = ++_operation;
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
      final downloading = _downloadingMessageId;
      if (downloading != null && downloading != messageId) {
        await _voiceCacheService.cancel(downloading);
      }
      await _player.stop();
      _position = Duration.zero;
      _duration = Duration.zero;
      final source = await _source(
        messageId: messageId,
        localPath: localPath,
        url: url,
        mimeType: mimeType,
      );
      if (operation != _operation) return;
      if (_manualEarpiece) {
        await setEarpiece(true);
      }
      _activeMessageId = messageId;
      notifyListeners();
      await _player.play(source);
    } catch (error) {
      _error = error;
      _playing = false;
      _activeMessageId = null;
      _manualEarpiece = false;
      unawaited(setEarpiece(false));
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stop() async {
    _operation++;
    final downloading = _downloadingMessageId;
    if (downloading != null) await _voiceCacheService.cancel(downloading);
    _downloadingMessageId = null;

    if (!_playing && _activeMessageId == null) {
      return;
    }

    await _player.stop();
    _playing = false;
    _activeMessageId = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _manualEarpiece = false;
    await setEarpiece(false);
    notifyListeners();
  }


  Future<void> playSendEffect() async {
    try {
      await _effectPlayer.stop();
      await _effectPlayer.play(
        BytesSource(_buildSendEffect(), mimeType: 'audio/wav'),
        volume: 0.42,
      );
    } catch (error) {
      debugPrint('[sendSound][failed] error=$error');
    }
  }

  static Uint8List _buildSendEffect() {
    const sampleRate = 22050;
    const durationMs = 185;
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
    var noiseSeed = 0x51f15e;
    var previousNoise = 0.0;
    for (var index = 0; index < sampleCount; index++) {
      final progress = index / sampleCount;
      final frequency = 720 + 2200 * math.pow(progress, 1.7);
      phase += 2 * math.pi * frequency / sampleRate;
      final envelope =
          progress < 0.06
              ? progress / 0.06
              : math.pow(1 - progress, 2.15).toDouble();
      noiseSeed = (noiseSeed * 1103515245 + 12345) & 0x7fffffff;
      final noise = noiseSeed / 0x7fffffff * 2 - 1;
      final airy = noise - previousNoise * 0.82;
      previousNoise = noise;
      final tonal =
          math.sin(phase) * 0.72 + math.sin(phase * 1.98 + 0.35) * 0.18;
      final tail = math.sin(phase * 0.51) * math.pow(1 - progress, 3) * 0.1;
      final sample =
          ((tonal + airy * 0.22 + tail) * envelope * 14500)
              .clamp(-32767, 32767)
              .round();
      bytes.setInt16(44 + index * 2, sample, Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  Future<Source> _source({
    required String messageId,
    String? localPath,
    String? url,
    String? mimeType,
  }) async {
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
    _downloadingMessageId = messageId;
    _downloadProgress = 0;
    notifyListeners();
    final cached = await _voiceCacheService.resolve(
      cacheKey: messageId,
      url: resolved,
      onProgress: (received, total) {
        _downloadProgress = total <= 0 ? 0 : received / total;
        notifyListeners();
      },
    );
    _downloadingMessageId = null;
    notifyListeners();
    if (cached != null) return DeviceFileSource(cached, mimeType: mimeType);
    return UrlSource(resolved, mimeType: mimeType);
  }

  Future<void> setEarpiece(bool value, {bool manual = false}) async {
    if (manual) {
      _manualEarpiece = value;
    }
    if (_earpiece == value) return;
    _earpiece = value;
    await _player.setAudioContext(
      AudioContextConfig(
        route:
            value
                ? AudioContextConfigRoute.earpiece
                : AudioContextConfigRoute.speaker,
      ).build(),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_stateSubscription.cancel());
    unawaited(_completionSubscription.cancel());
    unawaited(_proximitySubscription.cancel());
    unawaited(_positionSubscription.cancel());
    unawaited(_durationSubscription.cancel());
    unawaited(_player.dispose());
    unawaited(_effectPlayer.dispose());
    super.dispose();
  }
}
