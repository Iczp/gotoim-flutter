import 'package:flutter_test/flutter_test.dart';
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
}
