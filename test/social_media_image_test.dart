import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/app/application_providers.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/social/application/social_identity_controller.dart';
import 'package:gotoim_flutter/features/social/data/social_repository.dart';
import 'package:gotoim_flutter/features/social/presentation/widgets/social_media_image.dart';

class _Api extends Fake implements ApiClient {
  String? path;
  @override
  Future<List<int>> getBytes(String path, {Object? cancelTag, void Function(int, int)? onProgress}) async {
    this.path = path;
    return base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2foAAAAASUVORK5CYII=');
  }
}

void main() {
  testWidgets('relative Social media uses authenticated transport with current actor', (tester) async {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://gateway:8044\nSOCIAL_API_BASE_URL=http://social:51641');
    final api = _Api();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appEnvironmentProvider.overrideWithValue(AppEnvironment.fromDotEnv(AppFlavor.development)),
        socialApiClientProvider.overrideWithValue(api),
        socialIdentityProvider.overrideWith((ref) => SocialIdentityController(SocialRepository(api), chatObjectId: 1, name: 'Me')
          ..actor = const SocialActor(id: 'actor', name: 'Me', handle: 'me')),
      ],
      child: const MaterialApp(home: Scaffold(body: SocialMediaImage(url: '/api/social/media-assets/download/photo.png', fit: BoxFit.cover))),
    ));
    await tester.pump();
    expect(api.path, '/api/social/media-assets/download/photo.png?viewerActorId=actor');
    expect(find.byType(Image), findsOneWidget);
  });
}
