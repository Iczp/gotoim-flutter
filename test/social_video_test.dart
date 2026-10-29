import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/app/application_providers.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/core/network/token_storage.dart';
import 'package:gotoim_flutter/features/auth/application/auth_controller.dart';
import 'package:gotoim_flutter/features/social/application/social_identity_controller.dart';
import 'package:gotoim_flutter/features/social/application/social_publish_controller.dart';
import 'package:gotoim_flutter/features/social/data/social_repository.dart';
import 'package:gotoim_flutter/features/social/presentation/widgets/social_video_player.dart';
// The platform interface is supplied by the existing video_player dependency.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _Api extends Fake implements ApiClient {
  Map<String, Object?>? fields;
  Object? published;
  @override
  Future<T> postMultipart<T>(
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? extraFields,
    required MultipartUploadFile file,
    String fieldName = 'file',
    void Function(int, int)? onProgress,
    bool retryOnUnauthorized = true,
  }) async {
    fields = extraFields;
    onProgress?.call(5, 10);
    return {'id': 'video-asset'} as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async {
    published = data;
    return {'id': 'post', 'content': ''} as T;
  }

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async => null as T;
}

class _Token extends Fake implements TokenStorage {
  @override
  Future<String?> readAccessToken() async => 'test-token';
}

class _Video extends VideoPlayerPlatform {
  DataSource? source;
  @override
  Widget buildView(int playerId) => const SizedBox();
  @override
  Future<void> init() async {}
  @override
  Future<int?> create(DataSource dataSource) async {
    source = dataSource;
    return 1;
  }

  @override
  Future<void> dispose(int playerId) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 10),
      size: const Size(640, 360),
    ),
  );
}

void main() {
  test('video upload sends type, progress and publishes asset', () async {
    final api = _Api();
    final state = SocialPublishController(
      SocialRepository(api),
      actor: const SocialActor(id: 'actor', name: 'Me', handle: 'me'),
    );
    addTearDown(state.dispose);
    final progress = <double?>[];
    state.addListener(() {
      if (state.uploading) progress.add(state.uploadProgress);
    });
    final file = MultipartUploadFile(
      name: 'movie.mp4',
      length: 10,
      openRead: () => Stream.value(List.filled(10, 0)),
    );
    expect(await state.publish('', video: file), isNotNull);
    expect(api.fields, {'ownerActorId': 'actor', 'mediaType': 1});
    expect(progress, contains(0.5));
    expect((api.published as Map)['medias'], [
      {'mediaAssetId': 'video-asset', 'mediaType': 1, 'sortOrder': 0},
    ]);
    expect(await state.publish('', images: [file], video: file), isNull);
  });

  testWidgets(
    'Social video uses viewer and authorization without sending it to external origin',
    (tester) async {
      dotenv.loadFromString(
        envString:
            'API_BASE_URL=http://gateway\nSOCIAL_API_BASE_URL=http://social:51641',
      );
      final video = _Video();
      VideoPlayerPlatform.instance = video;
      final api = _Api();
      Widget host(String url) => ProviderScope(
        overrides: [
          appEnvironmentProvider.overrideWithValue(
            AppEnvironment.fromDotEnv(AppFlavor.development),
          ),
          socialApiClientProvider.overrideWithValue(api),
          tokenStorageProvider.overrideWithValue(_Token()),
          socialIdentityProvider.overrideWith(
            (ref) => SocialIdentityController(
              SocialRepository(api),
              chatObjectId: 1,
              name: 'Me',
            )..actor = const SocialActor(id: 'actor', name: 'Me', handle: 'me'),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: SocialVideoPlayer(url: url, active: false)),
        ),
      );
      await tester.pumpWidget(
        host('/api/social/media-assets/download/test.mp4'),
      );
      await tester.pump();
      await tester.pump();
      expect(
        video.source!.uri,
        'http://social:51641/api/social/media-assets/download/test.mp4?viewerActorId=actor',
      );
      expect(video.source!.httpHeaders['Authorization'], 'Bearer test-token');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(host('https://cdn.example/video.mp4'));
      await tester.pump();
      await tester.pump();
      expect(video.source!.uri, 'https://cdn.example/video.mp4');
      expect(video.source!.httpHeaders, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
