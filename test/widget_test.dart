import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/auth/domain/auth_session.dart';

void main() {
  test('parses the OpenIddict token response', () {
    final session = AuthSession.fromJson(<String, dynamic>{
      'access_token': 'access-token',
      'refresh_token': 'refresh-token',
      'expires_in': 3600,
    });

    expect(session.accessToken, 'access-token');
    expect(session.refreshToken, 'refresh-token');
    expect(session.expiresIn, const Duration(hours: 1));
  });
}
