import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/media/media_preview.dart';
import 'package:gotoim_flutter/core/media/video_playback_session.dart';

void main() {
  test(
    'ignores a late playback toggle after the session is disposed',
    () async {
      final session = VideoPlaybackSession.network('https://example.com/a.mp4');
      session.dispose();

      await expectLater(session.togglePlayback(), completes);
      expect(session.controller, isNull);
    },
  );

  test('formatMediaDuration formats seconds, minutes and hours correctly', () {
    expect(formatMediaDuration(const Duration(seconds: 15)), equals('00:15'));
    expect(formatMediaDuration(Duration.zero), equals('00:00'));
    expect(formatMediaDuration(const Duration(minutes: 1, seconds: 5)), equals('01:05'));
    expect(formatMediaDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), equals('01:02:03'));
  });
}

