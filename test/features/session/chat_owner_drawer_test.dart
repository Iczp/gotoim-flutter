import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/app/application_providers.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/network/abp/abp_current_user.dart';
import 'package:gotoim_flutter/core/realtime/signalr_gateway.dart';
import 'package:gotoim_flutter/features/auth/application/auth_controller.dart';
import 'package:gotoim_flutter/features/auth/domain/auth_repository.dart';
import 'package:gotoim_flutter/features/session/application/session_list_controller.dart';
import 'package:gotoim_flutter/features/session/data/models/chat_owner.dart';
import 'package:gotoim_flutter/features/session/presentation/chat_owner_drawer.dart';

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<Map<String, dynamic>> getUserInfo() async => {
    'preferred_username': 'testAdmin',
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSignalRGateway implements SignalRGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSessionListController extends ChangeNotifier
    implements SessionListController {
  _FakeSessionListController({this.owner});

  final ChatOwner? owner;

  @override
  ChatOwner? get currentOwner => owner;

  @override
  List<ChatOwner> get owners => owner != null ? [owner!] : const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'APP_NAME=Test'));

  group('formatCurrentUserAccountText', () {
    test('formats name and userName joined by two spaces', () {
      const user = AbpCurrentUser(name: 'IM', userName: 'admin');
      expect(formatCurrentUserAccountText(user), 'IM  admin');
    });

    test('deduplicates when name and userName are identical', () {
      const user = AbpCurrentUser(name: 'admin', userName: 'admin');
      expect(formatCurrentUserAccountText(user), 'admin');
    });

    test('returns userName when name is empty or whitespace', () {
      const user = AbpCurrentUser(name: '  ', userName: 'admin');
      expect(formatCurrentUserAccountText(user), 'admin');
    });

    test('returns name when userName is empty', () {
      const user = AbpCurrentUser(name: 'IM', userName: '');
      expect(formatCurrentUserAccountText(user), 'IM');
    });

    test('falls back to fallback string when user is null or empty', () {
      expect(
        formatCurrentUserAccountText(null, fallback: 'fallbackUser'),
        'fallbackUser',
      );
      const emptyUser = AbpCurrentUser();
      expect(
        formatCurrentUserAccountText(emptyUser, fallback: 'fallbackUser'),
        'fallbackUser',
      );
    });
  });

  group('CurrentUserAccountTile widget', () {
    testWidgets(
      'displays 当前账号：IM  admin when currentUser has name and userName',
      (tester) async {
        final fakeController = _FakeSessionListController(
          owner: const ChatOwner(
            id: 1,
            name: 'Goto个人身份',
            imageUrl: null,
            typeDescription: '个人',
          ),
        );

        const currentUser = AbpCurrentUser(
          name: 'IM',
          userName: 'admin',
          isAuthenticated: true,
        );

        final authController = AuthController(
          _FakeAuthRepository(),
          _FakeSignalRGateway(),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appEnvironmentProvider.overrideWithValue(
                AppEnvironment.fromDotEnv(AppFlavor.development),
              ),
              authControllerProvider.overrideWith((ref) => authController),
              currentUserProvider.overrideWithValue(currentUser),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: CurrentUserAccountTile(controller: fakeController),
              ),
            ),
          ),
        );

        expect(find.text('当前账号：IM  admin'), findsOneWidget);
        expect(find.text('当前身份：Goto个人身份'), findsOneWidget);
      },
    );

    testWidgets(
      'falls back to authController accountName when currentUser is null',
      (tester) async {
        final fakeController = _FakeSessionListController();
        final authController = AuthController(
          _FakeAuthRepository(),
          _FakeSignalRGateway(),
        );
        await authController.fetchUserInfo();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appEnvironmentProvider.overrideWithValue(
                AppEnvironment.fromDotEnv(AppFlavor.development),
              ),
              currentUserProvider.overrideWithValue(null),
              authControllerProvider.overrideWith((ref) => authController),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: CurrentUserAccountTile(controller: fakeController),
              ),
            ),
          ),
        );

        expect(find.text('当前账号：testAdmin'), findsOneWidget);
        expect(find.text('当前登录身份'), findsOneWidget);
      },
    );
  });
}
