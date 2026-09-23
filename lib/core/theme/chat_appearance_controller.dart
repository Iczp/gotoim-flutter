import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_theme_tokens.dart';

class ChatAppearanceSettings {
  const ChatAppearanceSettings({
    this.bubbleOpacity,
    this.composerHeight,
    this.messageMinHeight,
    this.glassBlurSigma,
    this.inputGlassOpacity,
    this.titleGlassOpacity,
    this.glassContentPadding,
    this.glassBorderOpacity,
    this.glassBorderWidth,
  });

  final double? bubbleOpacity;
  final double? composerHeight;
  final double? messageMinHeight;
  final double? glassBlurSigma;
  final double? inputGlassOpacity;
  final double? titleGlassOpacity;
  final double? glassContentPadding;
  final double? glassBorderOpacity;
  final double? glassBorderWidth;

  AppThemeTokens applyTo(AppThemeTokens tokens) => tokens.copyWith(
    chatBubbleOpacity: bubbleOpacity,
    chatComposerHeight: composerHeight,
    chatMessageMinHeight: messageMinHeight,
    chatGlassBlurSigma: glassBlurSigma,
    chatInputGlassOpacity: inputGlassOpacity,
    chatTitleGlassOpacity: titleGlassOpacity,
    chatGlassContentPadding: glassContentPadding,
    chatGlassBorderOpacity: glassBorderOpacity,
    chatGlassBorderWidth: glassBorderWidth,
  );

  ChatAppearanceSettings copyWith({
    double? bubbleOpacity,
    double? composerHeight,
    double? messageMinHeight,
    double? glassBlurSigma,
    double? inputGlassOpacity,
    double? titleGlassOpacity,
    double? glassContentPadding,
    double? glassBorderOpacity,
    double? glassBorderWidth,
  }) => ChatAppearanceSettings(
    bubbleOpacity: bubbleOpacity ?? this.bubbleOpacity,
    composerHeight: composerHeight ?? this.composerHeight,
    messageMinHeight: messageMinHeight ?? this.messageMinHeight,
    glassBlurSigma: glassBlurSigma ?? this.glassBlurSigma,
    inputGlassOpacity: inputGlassOpacity ?? this.inputGlassOpacity,
    titleGlassOpacity: titleGlassOpacity ?? this.titleGlassOpacity,
    glassContentPadding: glassContentPadding ?? this.glassContentPadding,
    glassBorderOpacity: glassBorderOpacity ?? this.glassBorderOpacity,
    glassBorderWidth: glassBorderWidth ?? this.glassBorderWidth,
  );

  /// Clears only the input/function-panel override, allowing the new theme
  /// default to take effect while preserving all other appearance settings.
  ChatAppearanceSettings withoutInputGlassOpacity() => ChatAppearanceSettings(
    bubbleOpacity: bubbleOpacity,
    composerHeight: composerHeight,
    messageMinHeight: messageMinHeight,
    glassBlurSigma: glassBlurSigma,
    titleGlassOpacity: titleGlassOpacity,
    glassContentPadding: glassContentPadding,
    glassBorderOpacity: glassBorderOpacity,
    glassBorderWidth: glassBorderWidth,
  );

  Map<String, double> toJson() => <String, double>{
    if (bubbleOpacity != null) 'bubbleOpacity': bubbleOpacity!,
    if (composerHeight != null) 'composerHeight': composerHeight!,
    if (messageMinHeight != null) 'messageMinHeight': messageMinHeight!,
    if (glassBlurSigma != null) 'glassBlurSigma': glassBlurSigma!,
    if (inputGlassOpacity != null) 'inputGlassOpacity': inputGlassOpacity!,
    if (titleGlassOpacity != null) 'titleGlassOpacity': titleGlassOpacity!,
    if (glassContentPadding != null)
      'glassContentPadding': glassContentPadding!,
    if (glassBorderOpacity != null) 'glassBorderOpacity': glassBorderOpacity!,
    if (glassBorderWidth != null) 'glassBorderWidth': glassBorderWidth!,
  };

  factory ChatAppearanceSettings.fromJson(Map<String, dynamic> json) =>
      ChatAppearanceSettings(
        bubbleOpacity: (json['bubbleOpacity'] as num?)?.toDouble(),
        composerHeight: (json['composerHeight'] as num?)?.toDouble(),
        messageMinHeight: (json['messageMinHeight'] as num?)?.toDouble(),
        glassBlurSigma: (json['glassBlurSigma'] as num?)?.toDouble(),
        inputGlassOpacity: (json['inputGlassOpacity'] as num?)?.toDouble(),
        titleGlassOpacity: (json['titleGlassOpacity'] as num?)?.toDouble(),
        glassContentPadding: (json['glassContentPadding'] as num?)?.toDouble(),
        glassBorderOpacity: (json['glassBorderOpacity'] as num?)?.toDouble(),
        glassBorderWidth: (json['glassBorderWidth'] as num?)?.toDouble(),
      );
}

class ChatAppearanceController extends Notifier<ChatAppearanceSettings> {
  static const _key = 'gotoim.chat-appearance.v1';
  static const _inputGlassOpacityMigrationKey =
      'gotoim.chat-appearance.input-glass-opacity.v2';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  var _changedLocally = false;

  @override
  ChatAppearanceSettings build() {
    _restore();
    return const ChatAppearanceSettings();
  }

  Future<void> _restore() async {
    try {
      final raw = await _storage.read(key: _key);
      if (_changedLocally) return;
      if (raw == null) {
        await _storage.write(key: _inputGlassOpacityMigrationKey, value: '1');
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        var restored = ChatAppearanceSettings.fromJson(decoded);
        final migrated = await _storage.read(
          key: _inputGlassOpacityMigrationKey,
        );
        if (migrated == null) {
          restored = restored.withoutInputGlassOpacity();
          await _storage.write(key: _key, value: jsonEncode(restored.toJson()));
          await _storage.write(key: _inputGlassOpacityMigrationKey, value: '1');
        }
        if (!_changedLocally) state = restored;
      }
    } catch (_) {}
  }

  Future<void> update(ChatAppearanceSettings settings) async {
    _changedLocally = true;
    state = settings;
    try {
      await _storage.write(key: _key, value: jsonEncode(settings.toJson()));
    } catch (_) {}
  }

  Future<void> reset() async {
    _changedLocally = true;
    state = const ChatAppearanceSettings();
    try {
      await _storage.delete(key: _key);
      await _storage.delete(key: _inputGlassOpacityMigrationKey);
    } catch (_) {}
  }
}

final chatAppearanceProvider =
    NotifierProvider<ChatAppearanceController, ChatAppearanceSettings>(
      ChatAppearanceController.new,
    );
