import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// User-controlled alert preferences. Conversation mute remains server-owned
/// and is evaluated in addition to these global switches.
class MessageAlertSettings extends ChangeNotifier {
  MessageAlertSettings({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _prefix = 'gotoim.message-alert.';
  final FlutterSecureStorage _storage;
  bool _notificationsEnabled = true;
  bool _vibrationEnabled = true;
  bool _soundEnabled = true;
  bool _activeChatVibrationEnabled = true;
  bool _previewEnabled = true;

  bool get notificationsEnabled => _notificationsEnabled;
  bool get vibrationEnabled => _vibrationEnabled;
  bool get soundEnabled => _soundEnabled;
  bool get activeChatVibrationEnabled => _activeChatVibrationEnabled;
  bool get previewEnabled => _previewEnabled;

  final Map<String, SessionMessageAlertSettings> _sessionCache =
      <String, SessionMessageAlertSettings>{};

  Future<SessionMessageAlertSettings> forSession(String sessionUnitId) async {
    final cached = _sessionCache[sessionUnitId];
    if (cached != null) return cached;
    final result = SessionMessageAlertSettings(
      notificationsEnabled: await _read('session.$sessionUnitId.notifications', _notificationsEnabled),
      soundEnabled: await _read('session.$sessionUnitId.sound', _soundEnabled),
      vibrationEnabled: await _read('session.$sessionUnitId.vibration', _vibrationEnabled),
      previewEnabled: await _read('session.$sessionUnitId.preview', _previewEnabled),
      activeChatVibrationEnabled: await _read('session.$sessionUnitId.active-chat-vibration', _activeChatVibrationEnabled),
    );
    _sessionCache[sessionUnitId] = result;
    return result;
  }

  Future<void> updateSession(
    String sessionUnitId, {
    bool? notificationsEnabled,
    bool? vibrationEnabled,
    bool? soundEnabled,
    bool? activeChatVibrationEnabled,
    bool? previewEnabled,
  }) async {
    final current = await forSession(sessionUnitId);
    final next = SessionMessageAlertSettings(
      notificationsEnabled: notificationsEnabled ?? current.notificationsEnabled,
      vibrationEnabled: vibrationEnabled ?? current.vibrationEnabled,
      soundEnabled: soundEnabled ?? current.soundEnabled,
      activeChatVibrationEnabled: activeChatVibrationEnabled ?? current.activeChatVibrationEnabled,
      previewEnabled: previewEnabled ?? current.previewEnabled,
    );
    _sessionCache[sessionUnitId] = next;
    await Future.wait([
      _storage.write(key: '${_prefix}session.$sessionUnitId.notifications', value: '${next.notificationsEnabled}'),
      _storage.write(key: '${_prefix}session.$sessionUnitId.vibration', value: '${next.vibrationEnabled}'),
      _storage.write(key: '${_prefix}session.$sessionUnitId.sound', value: '${next.soundEnabled}'),
      _storage.write(key: '${_prefix}session.$sessionUnitId.active-chat-vibration', value: '${next.activeChatVibrationEnabled}'),
      _storage.write(key: '${_prefix}session.$sessionUnitId.preview', value: '${next.previewEnabled}'),
    ]);
    notifyListeners();
  }

  Future<void> initialize() async {
    _notificationsEnabled = await _read('notifications', true);
    _vibrationEnabled = await _read('vibration', true);
    _soundEnabled = await _read('sound', true);
    _activeChatVibrationEnabled = await _read('active-chat-vibration', true);
    _previewEnabled = await _read('preview', true);
    notifyListeners();
  }

  Future<void> update({bool? notificationsEnabled, bool? vibrationEnabled, bool? soundEnabled, bool? activeChatVibrationEnabled, bool? previewEnabled}) async {
    if (notificationsEnabled != null) _notificationsEnabled = notificationsEnabled;
    if (vibrationEnabled != null) _vibrationEnabled = vibrationEnabled;
    if (soundEnabled != null) _soundEnabled = soundEnabled;
    if (activeChatVibrationEnabled != null) _activeChatVibrationEnabled = activeChatVibrationEnabled;
    if (previewEnabled != null) _previewEnabled = previewEnabled;
    await Future.wait([
      _storage.write(key: '${_prefix}notifications', value: '$_notificationsEnabled'),
      _storage.write(key: '${_prefix}vibration', value: '$_vibrationEnabled'),
      _storage.write(key: '${_prefix}sound', value: '$_soundEnabled'),
      _storage.write(key: '${_prefix}active-chat-vibration', value: '$_activeChatVibrationEnabled'),
      _storage.write(key: '${_prefix}preview', value: '$_previewEnabled'),
    ]);
    notifyListeners();
  }

  Future<bool> _read(String key, bool fallback) async =>
      (await _storage.read(key: '$_prefix$key'))?.toLowerCase() == 'false' ? false : fallback;
}

class SessionMessageAlertSettings {
  const SessionMessageAlertSettings({
    required this.notificationsEnabled,
    required this.vibrationEnabled,
    required this.soundEnabled,
    required this.activeChatVibrationEnabled,
    required this.previewEnabled,
  });

  final bool notificationsEnabled;
  final bool vibrationEnabled;
  final bool soundEnabled;
  final bool activeChatVibrationEnabled;
  final bool previewEnabled;
}

final messageAlertSettingsProvider = Provider<MessageAlertSettings>((ref) {
  final settings = MessageAlertSettings();
  ref.onDispose(settings.dispose);
  return settings;
});
